import { strict as assert } from "node:assert";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { createBlocklist, normalizeDomain } from "../src/blocklist.js";
import { createDNSWorker } from "../src/handler.js";
import { BLOCKED_RESPONSE_TTL, parseDNSMessage } from "../src/dns.js";
import { StatsDurableObject } from "../src/stats.js";
import type { WorkerEnvironment } from "../src/types.js";

const TOKEN = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO1234567890_-".slice(0, 43);

function qname(name: string): Uint8Array {
  const labels = name.replace(/\.$/, "").split(".");
  const bytes: number[] = [];
  for (const label of labels) bytes.push(label.length, ...[...label].map((character) => character.charCodeAt(0)));
  bytes.push(0);
  return Uint8Array.from(bytes);
}

function query(name = "www.example.com", type = 1, id = 0x1234, withEDNS = false): Uint8Array {
  const nameBytes = qname(name);
  const question = Uint8Array.from([...nameBytes, type >> 8, type & 0xff, 0, 1]);
  const opt = withEDNS ? Uint8Array.from([0, 0, 41, 0x10, 0, 0, 0, 0, 0, 0, 0]) : new Uint8Array();
  const result = new Uint8Array(12 + question.length + opt.length);
  result.set(Uint8Array.from([id >> 8, id & 0xff, 0x01, 0x10, 0, 1, 0, 0, 0, 0, 0, withEDNS ? 1 : 0]));
  result.set(question, 12);
  result.set(opt, 12 + question.length);
  return result;
}

function response(request: Uint8Array, type = 1, rcode = 0, ttl = 60): Uint8Array {
  const parsed = parseDNSMessage(request, 0);
  const question = parsed.questions[0].raw;
  const answer = type === 1
    ? Uint8Array.from([0xc0, 0x0c, 0, 1, 0, 1, ttl >> 24, (ttl >> 16) & 0xff, (ttl >> 8) & 0xff, ttl & 0xff, 0, 4, 1, 2, 3, 4])
    : new Uint8Array();
  const result = new Uint8Array(12 + question.length + answer.length);
  result.set(Uint8Array.from([
    request[0], request[1], 0x81, rcode === 0 ? 0x80 : 0x83, 0, 1,
    answer.length ? 0 : 0, answer.length ? 1 : 0, 0, 0, 0, 0,
  ]));
  result.set(question, 12);
  result.set(answer, 12 + question.length);
  return result;
}

function metadata(text: string, count = text.trim().split("\n").length) {
  return {
    schemaVersion: 1,
    version: "v0000000000000000",
    domainCount: count,
    textSHA256: createHash("sha256").update(text).digest("hex"),
  };
}

function binaryBody(data: Uint8Array): ArrayBuffer {
  return data.buffer as ArrayBuffer;
}

function makeWorker(
  text = "ads.example.com\ntracker.example.net\n",
  fetchImpl: typeof fetch = async () => new Response(null, { status: 500 }),
  options: Parameters<typeof createDNSWorker>[2] = {},
) {
  return createDNSWorker(text, metadata(text), { ...options, fetch: fetchImpl });
}

function requestFor(body: Uint8Array, method = "POST", headers: Record<string, string> = {}) {
  return requestForToken(body, TOKEN, method, headers);
}

function requestForToken(body: Uint8Array, token: string, method = "POST", headers: Record<string, string> = {}) {
  return new Request(`https://worker.example.test/${token}/dns-query`, {
    method,
    headers: { "content-type": "application/dns-message", ...headers },
    body: body.buffer as ArrayBuffer,
  });
}

function context() {
  const pending: Promise<unknown>[] = [];
  return { pending, waitUntil(promise: Promise<unknown>) { pending.push(promise); } };
}

test("health check identifies production without resolving DNS", async () => {
  let calls = 0;
  const worker = makeWorker(undefined, async () => { calls += 1; return new Response(null, { status: 500 }); });
  const result = await worker.fetch(new Request("https://worker.example.test/healthz"), { DEPLOYMENT_ENV: "production" }, context());
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { status: "ok", environment: "production" });
  assert.equal(calls, 0);
});

test("accepts valid POST and GET DoH messages with the wire content type", async () => {
  const incoming = query();
  let calls = 0;
  const worker = makeWorker(incoming.length ? "ads.example.com\ntracker.example.net\n" : "", async (url) => {
    calls += 1;
    assert.equal(url, "https://cloudflare-dns.com/dns-query");
    return new Response(binaryBody(response(incoming)), { status: 200, headers: { "content-type": "application/dns-message" } });
  });
  const post = await worker.fetch(requestFor(incoming), {}, context());
  assert.equal(post.status, 200);
  assert.equal(post.headers.get("content-type"), "application/dns-message");
  assert.deepEqual(new Uint8Array(await post.arrayBuffer()), response(incoming));
  const encoded = Buffer.from(incoming).toString("base64url");
  const get = await worker.fetch(new Request(`https://worker.example.test/${TOKEN}/dns-query?dns=${encoded}`), {}, context());
  assert.equal(get.status, 200);
  assert.equal(calls, 1, "GET should be served from the compatible cache");
});

test("does not serve an upstream response after its TTL expires", async () => {
  let clock = 1_000;
  let calls = 0;
  const incoming = query("ttl.example.com");
  const worker = makeWorker(undefined, async () => {
    calls += 1;
    return new Response(binaryBody(response(incoming, 1, 0, 1)), {
      headers: { "content-type": "application/dns-message" },
    });
  }, { now: () => clock });
  await worker.fetch(requestFor(incoming), {}, context());
  clock += 999;
  await worker.fetch(requestFor(incoming), {}, context());
  assert.equal(calls, 1);
  clock += 2;
  await worker.fetch(requestFor(incoming), {}, context());
  assert.equal(calls, 2);
});

test("cache hit replaces the upstream transaction ID with the current query ID", async () => {
  const first = query("same-cache-key.example.com", 1, 0x1111);
  const second = query("same-cache-key.example.com", 1, 0x2222);
  let clock = 1_000;
  let calls = 0;
  const worker = makeWorker(undefined, async (_url, init) => {
    calls += 1;
    const incoming = new Uint8Array(init?.body as ArrayBuffer);
    return new Response(binaryBody(response(incoming, 1, 0, 60)), {
      headers: { "content-type": "application/dns-message" },
    });
  }, { now: () => clock });

  const firstResponse = await worker.fetch(requestFor(first), {}, context());
  clock += 10_001;
  const secondResponse = await worker.fetch(requestFor(second), {}, context());
  assert.equal(parseDNSMessage(new Uint8Array(await firstResponse.arrayBuffer()), 1).id, 0x1111);
  const cached = parseDNSMessage(new Uint8Array(await secondResponse.arrayBuffer()), 1);
  assert.equal(cached.id, 0x2222);
  assert.equal(cached.records[0].ttl, 50);
  assert.equal(calls, 1);
});

test("does not share the in-memory response cache between installation tokens", async () => {
  const otherToken = "ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210_-abc12";
  const incoming = query("token-scoped-cache.example.com");
  let calls = 0;
  const worker = makeWorker(undefined, async (_url, init) => {
    calls += 1;
    const request = new Uint8Array(init?.body as ArrayBuffer);
    return new Response(binaryBody(response(request)), {
      headers: { "content-type": "application/dns-message" },
    });
  });

  await worker.fetch(requestFor(incoming), {}, context());
  await worker.fetch(requestForToken(incoming, otherToken), {}, context());
  assert.equal(calls, 2);
});

test("blocks exact names and descendants, but not lookalikes, without contacting an upstream", async () => {
  let calls = 0;
  const worker = makeWorker(undefined, async () => { calls += 1; return new Response(binaryBody(response(query("notads.example.com"))), { headers: { "content-type": "application/dns-message" } }); });
  const blockedContext = context();
  const blocked = await worker.fetch(requestFor(query("sub.ads.example.com")), {}, blockedContext);
  assert.equal(blocked.status, 200);
  assert.equal(parseDNSMessage(new Uint8Array(await blocked.arrayBuffer()), 1).questions[0].name, "sub.ads.example.com");
  assert.equal(calls, 0);
  const similar = await worker.fetch(requestFor(query("notads.example.com")), {}, context());
  assert.equal(similar.status, 200);
  assert.equal(calls, 1);
  await Promise.all(blockedContext.pending);
});

test("normalizes IDN names to the same A-label representation as the blocklist", () => {
  const normalized = normalizeDomain("Bücher.Example.");
  assert.equal(normalized, "xn--bcher-kva.example");
  assert.equal(normalizeDomain("example.com.."), null);
  const list = createBlocklist("xn--bcher-kva.example\n", metadata("xn--bcher-kva.example\n"));
  assert.equal(list.has("bücher.example."), true);
  assert.equal(list.has("other.example"), false);
});

test("keeps the transaction ID and EDNS record in a synthesized blocked response", async () => {
  const incoming = query("ads.example.com", 28, 0xbeef, true);
  const worker = makeWorker();
  const result = await worker.fetch(requestFor(incoming), {}, context());
  const bytes = new Uint8Array(await result.arrayBuffer());
  const parsed = parseDNSMessage(bytes, 1);
  assert.equal(parsed.id, 0xbeef);
  assert.equal(parsed.questions[0].type, 28);
  assert.equal(parsed.additionals.length, 1);
  assert.equal(parsed.records.length, 2);
  assert.equal(parsed.records[0].ttl, BLOCKED_RESPONSE_TTL);
});

test("does not fallback after a valid NXDOMAIN response", async () => {
  const incoming = query("unknown.example.com");
  const calls: string[] = [];
  const worker = makeWorker(undefined, async (url) => {
    calls.push(String(url));
    return new Response(binaryBody(response(incoming, 1, 3)), { status: 200, headers: { "content-type": "application/dns-message" } });
  });
  const result = await worker.fetch(requestFor(incoming), {}, context());
  assert.equal(result.status, 200);
  assert.equal(parseDNSMessage(new Uint8Array(await result.arrayBuffer()), 1).flags & 0xf, 3);
  assert.deepEqual(calls, ["https://cloudflare-dns.com/dns-query"]);
});

test("accepts the DNS query types used by browsers and applications", async () => {
  const types = [1, 28, 65, 64, 5, 16, 15, 2, 12, 6, 33];
  const worker = makeWorker(undefined, async (_url, init) => {
    const body = init?.body as ArrayBuffer;
    const incoming = new Uint8Array(body);
    return new Response(binaryBody(response(incoming, parseDNSMessage(incoming, 0).questions[0].type)), {
      status: 200,
      headers: { "content-type": "application/dns-message" },
    });
  });
  for (const [index, type] of types.entries()) {
    const result = await worker.fetch(requestFor(query(`type-${index}.example.com`, type)), {}, context());
    assert.equal(result.status, 200);
    assert.equal(parseDNSMessage(new Uint8Array(await result.arrayBuffer()), 1).questions[0].type, type);
  }
});

test("keeps concurrent responses isolated by transaction ID", async () => {
  const worker = makeWorker(undefined, async (_url, init) => {
    const incoming = new Uint8Array(init?.body as ArrayBuffer);
    return new Response(binaryBody(response(incoming)), {
      headers: { "content-type": "application/dns-message" },
    });
  });
  const requests = Array.from({ length: 32 }, (_, index) => query(`parallel-${index}.example.com`, 1, 0x4000 + index));
  const responses = await Promise.all(requests.map((request) => worker.fetch(requestFor(request), {}, context())));
  for (const [index, result] of responses.entries()) {
    assert.equal(result.status, 200);
    assert.equal(parseDNSMessage(new Uint8Array(await result.arrayBuffer()), 1).id, 0x4000 + index);
  }
});

test("uses Quad9 after primary transport failure and returns SERVFAIL if both fail", async () => {
  const incoming = query("allowed.example.com");
  const calls: string[] = [];
  const worker = makeWorker(undefined, async (url) => {
    calls.push(String(url));
    if (String(url).includes("cloudflare")) throw new Error("timeout");
    return new Response(binaryBody(response(incoming)), { status: 200, headers: { "content-type": "application/dns-message" } });
  });
  const fallback = await worker.fetch(requestFor(incoming), {}, context());
  assert.equal(fallback.status, 200);
  assert.equal(calls.length, 2);
  assert.match(calls[1], /quad9/);

  const failedWorker = makeWorker(undefined, async () => { throw new Error("network down"); });
  const failed = await failedWorker.fetch(requestFor(query("another.example.com")), {}, context());
  assert.equal(parseDNSMessage(new Uint8Array(await failed.arrayBuffer()), 1).flags & 0xf, 2);
});

test("falls back after an invalid upstream HTTP content type", async () => {
  const incoming = query("invalid-http.example.com");
  const calls: string[] = [];
  const worker = makeWorker(undefined, async (url) => {
    calls.push(String(url));
    if (calls.length === 1) return new Response("not dns", { status: 200, headers: { "content-type": "text/plain" } });
    return new Response(binaryBody(response(incoming)), { headers: { "content-type": "application/dns-message" } });
  });
  const result = await worker.fetch(requestFor(incoming), {}, context());
  assert.equal(result.status, 200);
  assert.equal(calls.length, 2);
});

test("falls back after an invalid upstream DNS payload", async () => {
  const incoming = query("invalid-dns.example.com");
  const calls: string[] = [];
  const worker = makeWorker(undefined, async (url) => {
    calls.push(String(url));
    if (calls.length === 1) return new Response(Uint8Array.from([1, 2, 3]), { headers: { "content-type": "application/dns-message" } });
    return new Response(binaryBody(response(incoming)), { headers: { "content-type": "application/dns-message" } });
  });
  const result = await worker.fetch(requestFor(incoming), {}, context());
  assert.equal(result.status, 200);
  assert.equal(calls.length, 2);
  assert.match(calls[1], /quad9/);
});

test("rejects malformed payloads, oversized requests, and unsupported methods", async () => {
  const worker = makeWorker();
  const malformed = await worker.fetch(requestFor(Uint8Array.from([1, 2, 3])), {}, context());
  assert.equal(malformed.status, 400);
  assert.equal(malformed.headers.get("content-type"), "application/dns-message");
  const tooLarge = await worker.fetch(requestFor(new Uint8Array(4097)), {}, context());
  assert.equal(tooLarge.status, 413);
  const badMethod = await worker.fetch(requestFor(query(), "PUT"), {}, context());
  assert.equal(badMethod.status, 405);
  const badContentType = await worker.fetch(requestFor(query(), "POST", { "content-type": "application/json" }), {}, context());
  assert.equal(badContentType.status, 415);
  assert.equal((await worker.fetch(new Request("https://worker.example.test/healthz", { method: "PUT" }), {}, context())).status, 405);
});

test("applies rate limiting without persisting the client IP", async () => {
  const worker = makeWorker(undefined, async () => new Response(binaryBody(response(query())), { headers: { "content-type": "application/dns-message" } }), { rateLimit: 1 });
  const headers = { "cf-connecting-ip": "203.0.113.10" };
  assert.equal((await worker.fetch(requestFor(query(), "POST", headers), {}, context())).status, 200);
  assert.equal((await worker.fetch(requestFor(query("second.example.com"), "POST", headers), {}, context())).status, 429);
});

test("rejects a blocklist whose metadata count or checksum is invalid", async () => {
  const text = "ads.example.com\n";
  const worker = createDNSWorker(text, { ...metadata(text), domainCount: 2 }, { fetch: async () => new Response(null, { status: 500 }) });
  const result = await worker.fetch(requestFor(query("allowed.example.com")), {}, context());
  assert.equal(result.status, 500);
});

test("never uses a plaintext DNS upstream", async () => {
  const worker = makeWorker(undefined, async (url) => {
    assert.match(String(url), /^https:\/\//);
    return new Response(binaryBody(response(query())), { headers: { "content-type": "application/dns-message" } });
  });
  await worker.fetch(requestFor(query("safe.example.com")), {}, context());
});

test("stores only an aggregate blocked total in the stats object", async () => {
  const values = new Map<string, unknown>();
  const state = {
    storage: {
      async get<T>(key: string) { return values.get(key) as T | undefined; },
      async put<T>(key: string, value: T) { values.set(key, value); },
    },
  };
  const object = new StatsDurableObject(state, {});
  assert.equal((await object.fetch(new Request("https://stats/increment", { method: "POST", body: '{"increment":1}' }))).status, 204);
  const result = await object.fetch(new Request("https://stats/total"));
  assert.deepEqual(await result.json(), { blockedTotal: 1, updatedAt: values.get("updatedAt") });
  assert.deepEqual([...values.keys()].sort(), ["blockedTotal", "updatedAt"]);
});

test("authenticates stats with the installation token", async () => {
  const namespace = {
    idFromName(name: string) {
      assert.equal(name, TOKEN);
      return name;
    },
    get() {
      return {
        async fetch(input: RequestInfo | URL) {
          assert.equal(String(input), "https://stats/total");
          return new Response(JSON.stringify({ blockedTotal: 8, updatedAt: "2026-08-26T00:00:00.000Z" }), {
            headers: { "content-type": "application/json" },
          });
        },
      };
    },
  };
  const worker = makeWorker();
  const unauthorized = await worker.fetch(new Request("https://worker.example.test/v1/stats"), { STATS: namespace }, context());
  assert.equal(unauthorized.status, 401);
  const authorized = await worker.fetch(new Request("https://worker.example.test/v1/stats", {
    headers: { authorization: `Bearer ${TOKEN}` },
  }), { STATS: namespace }, context());
  assert.deepEqual(await authorized.json(), { blockedTotal: 8, updatedAt: "2026-08-26T00:00:00.000Z" });
});

test("does not expose DNS responses to shared HTTP caches", async () => {
  const worker = makeWorker(undefined, async () => new Response(binaryBody(response(query())), {
    headers: { "content-type": "application/dns-message" },
  }));
  const result = await worker.fetch(requestFor(query("cache-header.example.com")), {}, context());
  assert.equal(result.headers.get("cache-control"), "no-store");
});
