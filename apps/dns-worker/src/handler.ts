import { createBlocklist, type Blocklist, type BlocklistMetadata } from "./blocklist.js";
import {
  blockedResponse,
  BLOCKED_RESPONSE_TTL,
  cacheKey,
  formErrorResponse,
  isValidUpstreamResponse,
  minimumTTL,
  parseDNSMessage,
  servfailResponse,
  withRemainingTTL,
  withTransactionID,
  DNSFormatError,
} from "./dns.js";
import type { WorkerEnvironment, WorkerExecutionContext } from "./types.js";

const MAX_QUERY_BYTES = 4096;
const MAX_CACHE_ENTRIES = 512;
const MAX_RATE_ENTRIES = 4096;
const UPSTREAM_TIMEOUT_MS = 1500;
const CIRCUIT_FAILURES = 3;
const CIRCUIT_OPEN_MS = 15_000;
const RATE_WINDOW_MS = 60_000;
const DEFAULT_RATE_LIMIT = 1200;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const CLOUDFLARE_DOH = "https://cloudflare-dns.com/dns-query";
const QUAD9_DOH = "https://dns.quad9.net/dns-query";

type FetchFunction = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

interface CacheEntry {
  response: Uint8Array;
  expiresAt: number;
}

interface RateEntry {
  start: number;
  count: number;
}

export interface WorkerDependencies {
  fetch?: FetchFunction;
  now?: () => number;
  rateLimit?: number;
  upstreamTimeoutMs?: number;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function dnsResponse(data: Uint8Array, status: number, ttl?: number): Response {
  // The Worker cache below is keyed by the complete query with its ID removed.
  // Keep HTTP caching disabled because a shared intermediary must never replay
  // a response containing another client's transaction ID.
  void ttl;
  const headers = new Headers({ "content-type": "application/dns-message", "cache-control": "no-store" });
  return new Response(data.buffer as ArrayBuffer, { status, headers });
}

function tokenFromPath(pathname: string): string | null {
  const parts = pathname.split("/");
  if (parts.length !== 3 || parts[0] !== "" || parts[2] !== "dns-query" || !TOKEN_PATTERN.test(parts[1])) return null;
  return parts[1];
}

function bearerToken(request: Request): string | null {
  const value = request.headers.get("authorization") ?? "";
  if (!value.startsWith("Bearer ")) return null;
  const token = value.slice(7);
  return TOKEN_PATTERN.test(token) ? token : null;
}

function stagingTokenStatus(env: WorkerEnvironment, token: string): "allowed" | "rejected" | "misconfigured" {
  if (env.DEPLOYMENT_ENV !== "staging") return "allowed";
  const allowedToken = env.STAGING_ALLOWED_DNS_TOKEN;
  if (!allowedToken || !TOKEN_PATTERN.test(allowedToken)) return "misconfigured";
  return token === allowedToken ? "allowed" : "rejected";
}

function decodeBase64URL(value: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]+$/.test(value) || value.length > 8192 || value.length % 4 === 1) return null;
  try {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (value.length % 4)) % 4);
    const binary = atob(padded);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

function contentTypeIsDNS(request: Request): boolean {
  const value = request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  return value === "application/dns-message";
}

async function requestBody(request: Request): Promise<{ data?: Uint8Array; error?: Response }> {
  const length = request.headers.get("content-length");
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_QUERY_BYTES)) return { error: new Response(null, { status: 413 }) };
  if (!request.body) return { data: new Uint8Array() };

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      total += next.value.byteLength;
      if (total > MAX_QUERY_BYTES) {
        await reader.cancel();
        return { error: new Response(null, { status: 413 }) };
      }
      chunks.push(next.value);
    }
  } catch {
    return { error: new Response(null, { status: 400 }) };
  } finally {
    reader.releaseLock();
  }

  const data = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.length;
  }
  return { data };
}

function isCircuitOpen(state: { failures: number; openedAt: number }, now: number): boolean {
  return state.failures >= CIRCUIT_FAILURES && now - state.openedAt < CIRCUIT_OPEN_MS;
}

export function createDNSWorker(blocklistText: string, metadata: BlocklistMetadata, dependencies: WorkerDependencies = {}) {
  const fetchImpl = dependencies.fetch ?? fetch;
  const now = dependencies.now ?? (() => Date.now());
  const rateLimit = dependencies.rateLimit ?? DEFAULT_RATE_LIMIT;
  const timeoutMs = dependencies.upstreamTimeoutMs ?? UPSTREAM_TIMEOUT_MS;
  const cache = new Map<string, CacheEntry>();
  const rateEntries = new Map<string, RateEntry>();
  const circuit = { failures: 0, openedAt: 0 };
  let blocklistPromise: Promise<Blocklist> | undefined;

  const loadBlocklist = (): Promise<Blocklist> => {
    blocklistPromise ??= (async () => {
      const blocklist = createBlocklist(blocklistText, metadata);
      if (metadata.textSHA256) {
        const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(blocklistText));
        const actual = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
        if (actual !== metadata.textSHA256) throw new Error("blocklist checksum mismatch");
      }
      return blocklist;
    })();
    return blocklistPromise;
  };

  const allowedByRate = (request: Request, token: string): boolean => {
    const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
    const key = `${token}:${ip}`;
    const timestamp = now();
    const previous = rateEntries.get(key);
    if (!previous || timestamp - previous.start >= RATE_WINDOW_MS) {
      if (rateEntries.size >= MAX_RATE_ENTRIES) {
        for (const [entryKey, entry] of rateEntries) {
          if (timestamp - entry.start >= RATE_WINDOW_MS) rateEntries.delete(entryKey);
          if (rateEntries.size < MAX_RATE_ENTRIES) break;
        }
        if (rateEntries.size >= MAX_RATE_ENTRIES) rateEntries.delete(rateEntries.keys().next().value as string);
      }
      rateEntries.set(key, { start: timestamp, count: 1 });
      return true;
    }
    previous.count += 1;
    return previous.count <= rateLimit;
  };

  const purgeExpiredCache = (timestamp: number): void => {
    for (const [key, entry] of cache) {
      if (entry.expiresAt <= timestamp) cache.delete(key);
    }
  };

  const recordBlocked = async (env: WorkerEnvironment, token: string): Promise<void> => {
    if (!env.STATS) return;
    try {
      const id = env.STATS.idFromName(token);
      await env.STATS.get(id).fetch("https://stats/increment", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: '{"increment":1}',
      });
    } catch {
      // Metrics are deliberately best effort and never delay DNS resolution.
    }
  };

  const resolveUpstream = async (query: Uint8Array, parsed: ReturnType<typeof parseDNSMessage>, url: string): Promise<{ response: Uint8Array; ttl: number }> => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const upstream = await fetchImpl(url, {
        method: "POST",
        headers: { accept: "application/dns-message", "content-type": "application/dns-message" },
        body: query.buffer as ArrayBuffer,
        signal: controller.signal,
      });
      const contentType = upstream.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
      if (!upstream.ok || upstream.status < 200 || upstream.status >= 300 || contentType !== "application/dns-message") {
        throw new Error("upstream http response is not dns wire format");
      }
      const body = new Uint8Array(await upstream.arrayBuffer());
      if (body.length === 0 || body.length > 65535) throw new Error("invalid upstream body");
      const responseParsed = isValidUpstreamResponse(parsed, body);
      return { response: body, ttl: minimumTTL(responseParsed) ?? 0 };
    } finally {
      clearTimeout(timeout);
    }
  };

  const fetchAllowed = async (query: Uint8Array, parsed: ReturnType<typeof parseDNSMessage>): Promise<{ response: Uint8Array; ttl: number }> => {
    const timestamp = now();
    if (!isCircuitOpen(circuit, timestamp)) {
      try {
        const result = await resolveUpstream(query, parsed, CLOUDFLARE_DOH);
        circuit.failures = 0;
        return result;
      } catch {
        circuit.failures += 1;
        if (circuit.failures >= CIRCUIT_FAILURES) circuit.openedAt = timestamp;
      }
    }
    try {
      const result = await resolveUpstream(query, parsed, QUAD9_DOH);
      return result;
    } catch {
      throw new Error("all upstreams failed");
    }
  };

  const fetchStats = async (env: WorkerEnvironment, token: string): Promise<Response> => {
    if (!env.STATS) return jsonResponse({ blockedTotal: 0, updatedAt: new Date(0).toISOString() });
    try {
      const id = env.STATS.idFromName(token);
      const response = await env.STATS.get(id).fetch("https://stats/total");
      if (!response.ok) return jsonResponse({ error: "temporarily unavailable" }, 503);
      const payload = await response.json() as { blockedTotal?: unknown; updatedAt?: unknown };
      if (!Number.isSafeInteger(payload.blockedTotal) || (payload.blockedTotal as number) < 0 || typeof payload.updatedAt !== "string") {
        return jsonResponse({ error: "temporarily unavailable" }, 503);
      }
      return jsonResponse({ blockedTotal: payload.blockedTotal, updatedAt: payload.updatedAt });
    } catch {
      return jsonResponse({ error: "temporarily unavailable" }, 503);
    }
  };

  return {
    async fetch(request: Request, env: WorkerEnvironment, context: WorkerExecutionContext): Promise<Response> {
      const url = new URL(request.url);
      if (url.pathname === "/healthz") {
        if (request.method !== "GET" && request.method !== "HEAD") {
          return new Response(null, { status: 405, headers: { allow: "GET, HEAD" } });
        }
        return jsonResponse({ status: "ok", environment: env.DEPLOYMENT_ENV ?? "unknown" });
      }
      if (url.pathname === "/v1/stats") {
        if (request.method !== "GET") return new Response(null, { status: 405, headers: { allow: "GET" } });
        const token = bearerToken(request);
        if (!token) return jsonResponse({ error: "unauthorized" }, 401);
        const tokenStatus = stagingTokenStatus(env, token);
        if (tokenStatus === "misconfigured") return jsonResponse({ error: "temporarily unavailable" }, 503);
        if (tokenStatus === "rejected") return jsonResponse({ error: "unauthorized" }, 401);
        if (!allowedByRate(request, token)) return jsonResponse({ error: "rate limited" }, 429);
        return fetchStats(env, token);
      }
      const token = tokenFromPath(url.pathname);
      if (!token) return new Response(null, { status: 404 });
      const tokenStatus = stagingTokenStatus(env, token);
      if (tokenStatus === "misconfigured") return new Response(null, { status: 503 });
      if (tokenStatus === "rejected") return new Response(null, { status: 401 });
      if (!allowedByRate(request, token)) return new Response(null, { status: 429, headers: { "retry-after": "60" } });

      let query: Uint8Array | undefined;
      if (request.method === "POST") {
        if (!contentTypeIsDNS(request)) return new Response(null, { status: 415 });
        const body = await requestBody(request);
        if (body.error) return body.error;
        query = body.data;
      } else if (request.method === "GET") {
        query = decodeBase64URL(url.searchParams.get("dns") ?? "") ?? undefined;
        if (!query || query.length > MAX_QUERY_BYTES) return new Response(null, { status: 400 });
      } else {
        return new Response(null, { status: 405, headers: { allow: "GET, POST" } });
      }
      if (!query || query.length < 2) return dnsResponse(formErrorResponse(query ?? new Uint8Array()), 400);
      let parsed: ReturnType<typeof parseDNSMessage>;
      try {
        parsed = parseDNSMessage(query, 0);
      } catch (error) {
        if (error instanceof DNSFormatError) return dnsResponse(formErrorResponse(query), 400);
        return new Response(null, { status: 400 });
      }
      try {
        const blocklist = await loadBlocklist();
        const question = parsed.questions[0];
        if (question.klass === 1 && blocklist.has(question.name)) {
          context.waitUntil(recordBlocked(env, token));
          return dnsResponse(blockedResponse(parsed), 200, BLOCKED_RESPONSE_TTL);
        }
        // Keep every installation in its own cache namespace. The current
        // response is global, but future entitlement or policy data must not
        // cross an installation boundary.
        const key = `${token}:${cacheKey(query)}`;
        const timestamp = now();
        purgeExpiredCache(timestamp);
        const cached = cache.get(key);
        if (cached && cached.expiresAt > timestamp) {
          const remainingTTL = Math.max(1, Math.ceil((cached.expiresAt - timestamp) / 1000));
          return dnsResponse(withTransactionID(withRemainingTTL(cached.response, remainingTTL), parsed.id), 200, remainingTTL);
        }
        cache.delete(key);
        try {
          const result = await fetchAllowed(query, parsed);
          if (result.ttl > 0) {
            const normalized = result.response.slice();
            normalized[0] = 0;
            normalized[1] = 0;
            if (cache.size >= MAX_CACHE_ENTRIES) cache.delete(cache.keys().next().value as string);
            cache.set(key, { response: normalized, expiresAt: now() + result.ttl * 1000 });
          }
          return dnsResponse(result.response, 200, result.ttl);
        } catch {
          return dnsResponse(servfailResponse(parsed), 200, 1);
        }
      } catch {
        return new Response(null, { status: 500 });
      }
    },
  };
}
