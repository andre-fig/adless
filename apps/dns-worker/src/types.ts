export interface StatsStorage {
  get<T>(key: string): Promise<T | undefined>;
  put<T>(key: string, value: T): Promise<void>;
}

export interface DurableObjectStateLike {
  storage: StatsStorage;
  blockConcurrencyWhile?<T>(callback: () => Promise<T>): Promise<T>;
}

export interface DurableObjectStubLike {
  fetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response>;
}

export interface DurableObjectNamespaceLike {
  idFromName(name: string): unknown;
  get(id: unknown): DurableObjectStubLike;
}

export interface KVNamespaceLike {
  get(key: string, type?: "json" | "text"): Promise<unknown>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
}

export interface WorkerEnvironment {
  AUTH?: KVNamespaceLike;
  STATS?: DurableObjectNamespaceLike;
  APPLE_BUNDLE_ID?: string;
  APPLE_APP_ID?: string;
  DEPLOYMENT_ENV?: "production";
}

export interface WorkerExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
}
