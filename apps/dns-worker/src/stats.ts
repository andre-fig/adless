import type { DurableObjectStateLike, WorkerEnvironment } from "./types.js";

export class StatsDurableObject {
  private readonly state: DurableObjectStateLike;

  constructor(state: DurableObjectStateLike, _env: WorkerEnvironment) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
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
