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

export interface WorkerEnvironment {
  STATS?: DurableObjectNamespaceLike;
}

export interface WorkerExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
}
