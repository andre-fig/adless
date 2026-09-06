import type {
  DurableObjectStateLike,
  StatsStorage,
  SubscriptionAuthorityEvent,
  WorkerEnvironment,
} from "./types.js";

const AUTHORITY_CHAIN_KEY = "authority:chain";
const AUTHORITY_LATEST_KEY = "authority:latest";
const BLOCKING_ENABLED_KEY = "blockingEnabled";

function isSafeIdentifier(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 128;
}

function isAuthorityEvent(value: unknown): value is SubscriptionAuthorityEvent {
  if (!value || typeof value !== "object") return false;
  const event = value as Partial<SubscriptionAuthorityEvent>;
  return event.schemaVersion === 1
    && (event.source === "record" || event.source === "transaction" || event.source === "notification")
    && isSafeIdentifier(event.sourceId)
    && typeof event.reason === "string"
    && event.reason.length > 0
    && event.reason.length <= 64
    && (event.environment === "Production" || event.environment === "Sandbox" || event.environment === "Xcode")
    && isSafeIdentifier(event.originalTransactionId)
    && (event.transactionId === undefined || isSafeIdentifier(event.transactionId))
    && isSafeIdentifier(event.productId)
    && (event.status === "active" || event.status === "expired" || event.status === "revoked")
    && Number.isSafeInteger(event.accessUntil)
    && (event.accessUntil ?? -1) >= 0
    && typeof event.inGracePeriod === "boolean"
    && typeof event.isInBillingRetryPeriod === "boolean"
    && Number.isSafeInteger(event.periodPurchaseDate)
    && (event.periodPurchaseDate ?? -1) >= 0
    && Number.isSafeInteger(event.periodExpiresDate)
    && (event.periodExpiresDate ?? -1) >= 0
    && Number.isSafeInteger(event.signedDate)
    && (event.signedDate ?? 0) > 0;
}

function compareAuthorityEvents(left: SubscriptionAuthorityEvent, right: SubscriptionAuthorityEvent): number {
  const sameTransaction = left.transactionId !== undefined
    && left.transactionId === right.transactionId;
  if (!sameTransaction) {
    // Apple purchase dates are the authoritative period order when both
    // events carry one. Legacy KV records only retain accessUntil and use 0;
    // those remain on the conservative expiry fallback during rollout.
    const hasComparablePurchaseDates = left.periodPurchaseDate > 0 && right.periodPurchaseDate > 0;
    if (hasComparablePurchaseDates && left.periodPurchaseDate !== right.periodPurchaseDate) {
      return left.periodPurchaseDate - right.periodPurchaseDate;
    }
    if (left.periodExpiresDate !== right.periodExpiresDate) {
      return left.periodExpiresDate - right.periodExpiresDate;
    }
  }
  // A generic/re-signed Transaction is only a baseline for its period. Once
  // Apple sends a notification correction for that period, another copy of
  // the Transaction cannot undo it. A migrated terminal record has the same
  // conservative weight. Explicit recovery is a newer notification.
  const correctionRank = (event: SubscriptionAuthorityEvent): number => (event.source === "notification"
    && (event.status !== "active" || event.reason !== "DID_FAIL_TO_RENEW"))
    || (event.source === "record" && event.status !== "active")
    ? 2
    : event.source === "transaction" || event.source === "notification"
      ? 1
      : 0;
  const leftCorrectionRank = correctionRank(left);
  const rightCorrectionRank = correctionRank(right);
  if (leftCorrectionRank !== rightCorrectionRank) return leftCorrectionRank - rightCorrectionRank;
  if (leftCorrectionRank > 0 && left.signedDate !== right.signedDate) {
    return left.signedDate - right.signedDate;
  }
  const rank = { active: 0, expired: 1, revoked: 2 } as const;
  if (rank[left.status] !== rank[right.status]) return rank[left.status] - rank[right.status];
  if (left.sourceId === right.sourceId) return 0;
  return left.sourceId < right.sourceId ? -1 : 1;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function authorityEventKey(event: SubscriptionAuthorityEvent): Promise<string> {
  const expiresDate = String(event.periodExpiresDate).padStart(16, "0");
  const purchaseDate = String(event.periodPurchaseDate).padStart(16, "0");
  const sourceRank = event.source === "notification" ? "2" : event.source === "transaction" ? "1" : "0";
  const sourceDate = String(event.signedDate).padStart(16, "0");
  const rank = event.status === "revoked" ? "2" : event.status === "expired" ? "1" : "0";
  return `authority:event:${expiresDate}:${purchaseDate}:${sourceRank}:${sourceDate}:${rank}:${await sha256Hex(`${event.source}:${event.sourceId}`)}`;
}

function authorityChain(event: SubscriptionAuthorityEvent): string {
  return `${event.environment}\u0000${event.originalTransactionId}`;
}

export class StatsDurableObject {
  private readonly state: DurableObjectStateLike;

  constructor(state: DurableObjectStateLike, _env: WorkerEnvironment) {
    this.state = state;
  }

  private async applyAuthorityEvent(event: SubscriptionAuthorityEvent): Promise<SubscriptionAuthorityEvent> {
    const eventKey = await authorityEventKey(event);
    const apply = async (storage: StatsStorage): Promise<SubscriptionAuthorityEvent> => {
      const [storedChain, existingEvent, current] = await Promise.all([
        storage.get<string>(AUTHORITY_CHAIN_KEY),
        storage.get<SubscriptionAuthorityEvent>(eventKey),
        storage.get<SubscriptionAuthorityEvent>(AUTHORITY_LATEST_KEY),
      ]);
      const chain = authorityChain(event);
      if (storedChain !== undefined && storedChain !== chain) {
        throw new Error("authority chain mismatch");
      }
      if (existingEvent !== undefined && JSON.stringify(existingEvent) !== JSON.stringify(event)) {
        throw new Error("authority event conflict");
      }
      if (storedChain === undefined) await storage.put(AUTHORITY_CHAIN_KEY, chain);
      if (existingEvent === undefined) await storage.put(eventKey, event);
      const latest = !current || compareAuthorityEvents(event, current) > 0 ? event : current;
      if (!current || compareAuthorityEvents(latest, current) !== 0) {
        await storage.put(AUTHORITY_LATEST_KEY, latest);
      }
      return latest;
    };

    if (this.state.storage.transaction) {
      return await this.state.storage.transaction(apply);
    }
    if (this.state.blockConcurrencyWhile) {
      return await this.state.blockConcurrencyWhile(() => apply(this.state.storage));
    }
    return await apply(this.state.storage);
  }

  async fetch(request: Request): Promise<Response> {
    const pathname = new URL(request.url).pathname;
    if (pathname === "/blocking") {
      if (request.method === "GET") {
        const blockingEnabled = await this.state.storage.get<boolean>(BLOCKING_ENABLED_KEY) ?? true;
        return new Response(JSON.stringify({ blockingEnabled }), {
          headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
        });
      }
      if (request.method !== "PUT") {
        return new Response(null, { status: 405, headers: { allow: "GET, PUT" } });
      }
      let payload: unknown;
      try {
        payload = await request.json();
      } catch {
        return new Response(null, { status: 400 });
      }
      const blockingEnabled = payload && typeof payload === "object"
        ? (payload as { blockingEnabled?: unknown }).blockingEnabled
        : undefined;
      if (typeof blockingEnabled !== "boolean") return new Response(null, { status: 400 });
      await this.state.storage.put(BLOCKING_ENABLED_KEY, blockingEnabled);
      return new Response(JSON.stringify({ blockingEnabled }), {
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      });
    }
    if (pathname === "/authority/latest") {
      if (request.method !== "GET") return new Response(null, { status: 405, headers: { allow: "GET" } });
      const event = await this.state.storage.get<SubscriptionAuthorityEvent>(AUTHORITY_LATEST_KEY);
      if (event !== undefined && !isAuthorityEvent(event)) return new Response(null, { status: 500 });
      return new Response(JSON.stringify({ event: event ?? null }), {
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      });
    }
    if (pathname === "/authority/event") {
      if (request.method !== "POST") return new Response(null, { status: 405, headers: { allow: "POST" } });
      let payload: unknown;
      try {
        payload = await request.json();
      } catch {
        return new Response(null, { status: 400 });
      }
      const event = payload && typeof payload === "object"
        ? (payload as { event?: unknown }).event
        : undefined;
      if (!isAuthorityEvent(event)) return new Response(null, { status: 400 });
      try {
        const latest = await this.applyAuthorityEvent(event);
        return new Response(JSON.stringify({ event: latest }), {
          headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
        });
      } catch (error) {
        if (error instanceof Error
          && (error.message === "authority chain mismatch" || error.message === "authority event conflict")) {
          return new Response(null, { status: 409 });
        }
        throw error;
      }
    }
    if (request.method === "GET") {
      const blockedTotal = await this.state.storage.get<number>("blockedTotal") ?? 0;
      const updatedAt = await this.state.storage.get<string>("updatedAt") ?? new Date(0).toISOString();
      return new Response(JSON.stringify({ blockedTotal, updatedAt }), {
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      });
    }
    if (request.method !== "POST") return new Response(null, { status: 405, headers: { allow: "GET, POST" } });
    let payload: unknown;
    try {
      payload = await request.json();
    } catch {
      return new Response(null, { status: 400 });
    }
    if (!payload || typeof payload !== "object" || (payload as { increment?: unknown }).increment !== 1) {
      return new Response(null, { status: 400 });
    }
    const increment = async (): Promise<void> => {
      const current = await this.state.storage.get<number>("blockedTotal") ?? 0;
      const next = current + 1;
      await this.state.storage.put("blockedTotal", next);
      await this.state.storage.put("updatedAt", new Date().toISOString());
    };
    if (this.state.blockConcurrencyWhile) {
      await this.state.blockConcurrencyWhile(increment);
    } else {
      await increment();
    }
    return new Response(null, { status: 204 });
  }
}
