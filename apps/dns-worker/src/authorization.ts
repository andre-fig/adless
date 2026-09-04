import { verifyAppleJWS, type AppleJWSVerificationOptions } from "./apple-jws.js";

const AUTH_KEY_PREFIX = "adless:auth:v1:";
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const INSTALLATION_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PRODUCT_IDS = new Set([
  "com.orbeworks.adless.pro.monthly",
  "com.orbeworks.adless.pro.yearly",
]);
const MAX_INSTALLATIONS_PER_SUBSCRIPTION = 8;
const NOTIFICATION_TTL_SECONDS = 60 * 60 * 24 * 45;

export type AuthorizationStatus = "active" | "expired" | "revoked";
export type TokenRole = "dns" | "stats";
export type AppleEnvironment = "Production" | "Sandbox";

export interface AuthorizationKV {
  get(key: string, type?: "json" | "text"): Promise<unknown>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
}

export interface AuthorizationRecord {
  schemaVersion: 1;
  installationId: string;
  dnsTokenHash: string;
  statsTokenHash: string;
  originalTransactionId: string;
  productId: string;
  environment: AppleEnvironment;
  status: AuthorizationStatus;
  accessUntil: number;
  inGracePeriod: boolean;
  isInBillingRetryPeriod: boolean;
  updatedAt: number;
  lastSignedDate: number;
}

interface TokenRecord {
  schemaVersion: 1;
  installationId: string;
  role: TokenRole;
}

interface SubscriptionInstallations {
  schemaVersion: 1;
  installationIds: string[];
}

export interface AppleTransactionPayload {
  bundleId: string;
  environment: AppleEnvironment;
  productId: string;
  originalTransactionId: string;
  transactionId: string;
  expiresDate?: number;
  revocationDate?: number;
  signedDate: number;
  type?: string;
}

export interface AppleRenewalInfoPayload {
  environment: AppleEnvironment;
  originalTransactionId: string;
  productId?: string;
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

export interface AppleNotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  signedDate: number;
  data?: {
    appAppleId?: number;
    bundleId?: string;
    environment?: AppleEnvironment;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

export type TokenAuthorization =
  | { kind: "active" | "expired"; installationId: string }
  | { kind: "rejected"; reason: "unknown" | "forbidden" };

export interface AuthorizationEnvironment {
  AUTH?: AuthorizationKV;
  APPLE_BUNDLE_ID?: string;
  APPLE_APP_ID?: string;
}

export interface AuthorizationDependencies {
  now?: () => number;
  verifyTransaction?: (jws: string) => Promise<AppleTransactionPayload>;
  verifyNotification?: (jws: string) => Promise<AppleNotificationPayload>;
  verifyRenewalInfo?: (jws: string) => Promise<AppleRenewalInfoPayload>;
  appleJWSOptions?: AppleJWSVerificationOptions;
}

function authKey(suffix: string): string {
  return `${AUTH_KEY_PREFIX}${suffix}`;
}

function installationKey(installationId: string): string {
  return authKey(`installation:${installationId}`);
}

function tokenKey(hash: string): string {
  return authKey(`token:${hash}`);
}

function subscriptionKey(originalTransactionId: string): string {
  return authKey(`subscription:${originalTransactionId}`);
}

function notificationKey(notificationUUID: string): string {
  return authKey(`notification:${notificationUUID}`);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object";
}

async function readJSON<T>(kv: AuthorizationKV, key: string): Promise<T | null> {
  const value = await kv.get(key, "json");
  return isRecord(value) ? value as T : null;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function validTransaction(transaction: AppleTransactionPayload, env: AuthorizationEnvironment): boolean {
  return transaction.bundleId === (env.APPLE_BUNDLE_ID ?? "com.orbeworks.adless")
    && (transaction.environment === "Production" || transaction.environment === "Sandbox")
    && PRODUCT_IDS.has(transaction.productId)
    && typeof transaction.originalTransactionId === "string"
    && transaction.originalTransactionId.length > 0
    && typeof transaction.transactionId === "string"
    && transaction.transactionId.length > 0
    && Number.isSafeInteger(transaction.signedDate)
    && (transaction.expiresDate === undefined || Number.isSafeInteger(transaction.expiresDate));
}

function validNotification(notification: AppleNotificationPayload, env: AuthorizationEnvironment): boolean {
  const data = notification.data;
  const configuredAppAppleId = env.APPLE_APP_ID ? Number(env.APPLE_APP_ID) : undefined;
  const appAppleIdMatches = configuredAppAppleId === undefined
    || (Number.isSafeInteger(configuredAppAppleId) && data?.appAppleId === configuredAppAppleId);
  return typeof notification.notificationType === "string"
    && typeof notification.notificationUUID === "string"
    && notification.notificationUUID.length > 0
    && Number.isSafeInteger(notification.signedDate)
    && appAppleIdMatches
    && (!data?.bundleId || data.bundleId === (env.APPLE_BUNDLE_ID ?? "com.orbeworks.adless"))
    && (!data?.environment || data.environment === "Production" || data.environment === "Sandbox");
}

function validInstallationId(installationId: string): boolean {
  return INSTALLATION_ID_PATTERN.test(installationId);
}

function recordIsActive(record: AuthorizationRecord, now: number): boolean {
  return record.status === "active" && record.accessUntil > now;
}

export async function authorizeToken(
  env: AuthorizationEnvironment,
  token: string,
  role: TokenRole,
  now = Date.now(),
): Promise<TokenAuthorization> {
  if (!env.AUTH || !TOKEN_PATTERN.test(token)) return { kind: "rejected", reason: "unknown" };
  const tokenHash = await sha256Hex(token);
  const mapping = await readJSON<TokenRecord>(env.AUTH, tokenKey(tokenHash));
  if (!mapping || mapping.schemaVersion !== 1 || mapping.role !== role || !validInstallationId(mapping.installationId)) {
    return { kind: "rejected", reason: "unknown" };
  }

  const record = await readJSON<AuthorizationRecord>(env.AUTH, installationKey(mapping.installationId));
  if (!record || record.schemaVersion !== 1 || record.installationId !== mapping.installationId) {
    return { kind: "rejected", reason: "unknown" };
  }
  const currentHash = role === "dns" ? record.dnsTokenHash : record.statsTokenHash;
  if (currentHash !== tokenHash) return { kind: "rejected", reason: "unknown" };
  if (record.status === "revoked") return { kind: "rejected", reason: "forbidden" };
  const active = recordIsActive(record, now);
  if (role === "stats" && !active) return { kind: "rejected", reason: "forbidden" };
  return { kind: active ? "active" : "expired", installationId: mapping.installationId };
}

function statusFromTransaction(transaction: AppleTransactionPayload, now: number): AuthorizationStatus {
  if (transaction.revocationDate !== undefined) return "revoked";
  return (transaction.expiresDate ?? 0) > now ? "active" : "expired";
}

async function addSubscriptionInstallation(kv: AuthorizationKV, transactionId: string, installationId: string): Promise<void> {
  const current = await readJSON<SubscriptionInstallations>(kv, subscriptionKey(transactionId));
  const installationIds = current?.installationIds.filter(validInstallationId) ?? [];
  if (!installationIds.includes(installationId)) installationIds.push(installationId);
  await kv.put(subscriptionKey(transactionId), JSON.stringify({
    schemaVersion: 1,
    installationIds: installationIds.slice(-MAX_INSTALLATIONS_PER_SUBSCRIPTION),
  }));
}

async function removeTokenMapping(kv: AuthorizationKV, hash: string | undefined): Promise<void> {
  if (hash) await kv.delete(tokenKey(hash));
}

export async function registerInstallation(
  env: AuthorizationEnvironment,
  installationId: string,
  transaction: AppleTransactionPayload,
  now = Date.now(),
): Promise<{ dnsToken: string; statsToken: string; installationId: string; accessUntil: number }> {
  if (!env.AUTH) throw new Error("authorization storage is not configured");
  if (!validInstallationId(installationId) || !validTransaction(transaction, env)) {
    throw new Error("invalid authorization data");
  }
  const accessUntil = transaction.expiresDate ?? 0;
  if (transaction.revocationDate !== undefined || accessUntil <= now) {
    throw new Error("transaction does not grant access");
  }

  const previous = await readJSON<AuthorizationRecord>(env.AUTH, installationKey(installationId));
  await removeTokenMapping(env.AUTH, previous?.dnsTokenHash);
  await removeTokenMapping(env.AUTH, previous?.statsTokenHash);

  const dnsToken = randomToken();
  const statsToken = randomToken();
  const [dnsTokenHash, statsTokenHash] = await Promise.all([sha256Hex(dnsToken), sha256Hex(statsToken)]);
  const record: AuthorizationRecord = {
    schemaVersion: 1,
    installationId,
    originalTransactionId: transaction.originalTransactionId,
    productId: transaction.productId,
    environment: transaction.environment,
    status: statusFromTransaction(transaction, now),
    accessUntil,
    inGracePeriod: false,
    isInBillingRetryPeriod: false,
    updatedAt: now,
    lastSignedDate: transaction.signedDate,
    dnsTokenHash,
    statsTokenHash,
  };

  await env.AUTH.put(installationKey(installationId), JSON.stringify(record));
  await env.AUTH.put(tokenKey(dnsTokenHash), JSON.stringify({ schemaVersion: 1, installationId, role: "dns" }));
  await env.AUTH.put(tokenKey(statsTokenHash), JSON.stringify({ schemaVersion: 1, installationId, role: "stats" }));
  await addSubscriptionInstallation(env.AUTH, transaction.originalTransactionId, installationId);
  return { dnsToken, statsToken, installationId, accessUntil };
}

function nextRecordFromNotification(
  current: AuthorizationRecord,
  notification: AppleNotificationPayload,
  transaction: AppleTransactionPayload | undefined,
  renewal: AppleRenewalInfoPayload | undefined,
  now: number,
): AuthorizationRecord {
  const type = notification.notificationType;
  const forceRevoke = type === "REFUND" || type === "REVOKE";
  if (forceRevoke) {
    return {
      ...current,
      status: "revoked",
      inGracePeriod: false,
      isInBillingRetryPeriod: false,
      updatedAt: now,
      lastSignedDate: Math.max(current.lastSignedDate, notification.signedDate),
    };
  }

  const transactionExpiry = transaction?.expiresDate ?? current.accessUntil;
  const graceExpiry = renewal?.gracePeriodExpiresDate ?? 0;
  const accessUntil = Math.max(transactionExpiry, graceExpiry);
  const isExpiredNotification = type === "EXPIRED" || type === "GRACE_PERIOD_EXPIRED";
  const effectiveStatus: AuthorizationStatus = isExpiredNotification || accessUntil <= now ? "expired" : "active";
  const inGracePeriod = !isExpiredNotification && graceExpiry > now;
  const isInBillingRetryPeriod = renewal?.isInBillingRetryPeriod ?? current.isInBillingRetryPeriod ?? false;
  const signedDate = Math.max(current.lastSignedDate, notification.signedDate, transaction?.signedDate ?? 0);

  if (notification.signedDate < current.lastSignedDate && !transaction?.revocationDate) return current;
  return {
    ...current,
    productId: transaction?.productId ?? renewal?.productId ?? current.productId,
    status: effectiveStatus,
    accessUntil,
    inGracePeriod,
    isInBillingRetryPeriod,
    updatedAt: now,
    lastSignedDate: signedDate,
  };
}

export async function processAppleNotification(
  env: AuthorizationEnvironment,
  notification: AppleNotificationPayload,
  transaction: AppleTransactionPayload | undefined,
  renewal: AppleRenewalInfoPayload | undefined,
  now = Date.now(),
): Promise<void> {
  if (!env.AUTH) throw new Error("authorization storage is not configured");
  const originalTransactionId = transaction?.originalTransactionId ?? renewal?.originalTransactionId;
  if (!originalTransactionId) return;
  const subscriptions = await readJSON<SubscriptionInstallations>(env.AUTH, subscriptionKey(originalTransactionId));
  for (const installationId of subscriptions?.installationIds ?? []) {
    if (!validInstallationId(installationId)) continue;
    const current = await readJSON<AuthorizationRecord>(env.AUTH, installationKey(installationId));
    if (!current || current.originalTransactionId !== originalTransactionId) continue;
    const next = nextRecordFromNotification(current, notification, transaction, renewal, now);
    await env.AUTH.put(installationKey(installationId), JSON.stringify({
      ...next,
      dnsTokenHash: current.dnsTokenHash,
      statsTokenHash: current.statsTokenHash,
    }));
  }
}

async function readJSONBody(request: Request, maxBytes: number): Promise<Record<string, unknown> | null> {
  const length = request.headers.get("content-length");
  if (length && (!/^\d+$/.test(length) || Number(length) > maxBytes)) return null;
  const body = await request.arrayBuffer();
  if (body.byteLength > maxBytes) return null;
  try {
    const value: unknown = JSON.parse(new TextDecoder().decode(body));
    return isRecord(value) ? value : null;
  } catch {
    return null;
  }
}

export async function handleAuthorizationRegister(
  request: Request,
  env: AuthorizationEnvironment,
  dependencies: AuthorizationDependencies = {},
): Promise<Response> {
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { allow: "POST" } });
  const body = await readJSONBody(request, 128 * 1024);
  const installationId = typeof body?.installationId === "string" ? body.installationId : "";
  const transactionJWS = typeof body?.transactionJWS === "string" ? body.transactionJWS : "";
  if (!validInstallationId(installationId) || transactionJWS.length === 0 || transactionJWS.length > 128 * 1024) {
    return jsonResponse({ error: "invalid request" }, 400);
  }

  try {
    const transaction = dependencies.verifyTransaction
      ? await dependencies.verifyTransaction(transactionJWS)
      : await verifyAppleJWS<AppleTransactionPayload>(transactionJWS, dependencies.appleJWSOptions);
    const result = await registerInstallation(env, installationId, transaction, dependencies.now?.() ?? Date.now());
    return jsonResponse(result);
  } catch {
    return jsonResponse({ error: "transaction not authorized" }, 401);
  }
}

export async function handleAppleNotification(
  request: Request,
  env: AuthorizationEnvironment,
  dependencies: AuthorizationDependencies = {},
): Promise<Response> {
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { allow: "POST" } });
  const body = await readJSONBody(request, 160 * 1024);
  const signedPayload = typeof body?.signedPayload === "string" ? body.signedPayload : "";
  if (!signedPayload) return jsonResponse({ error: "invalid request" }, 400);

  try {
    const notification = dependencies.verifyNotification
      ? await dependencies.verifyNotification(signedPayload)
      : await verifyAppleJWS<AppleNotificationPayload>(signedPayload, dependencies.appleJWSOptions);
    if (!validNotification(notification, env) || !env.AUTH) return jsonResponse({ error: "invalid notification" }, 400);
    if (await env.AUTH.get(notificationKey(notification.notificationUUID), "text")) return jsonResponse({ ok: true });

    const transactionJWS = notification.data?.signedTransactionInfo;
    const renewalJWS = notification.data?.signedRenewalInfo;
    const transaction = transactionJWS
      ? dependencies.verifyTransaction
        ? await dependencies.verifyTransaction(transactionJWS)
        : await verifyAppleJWS<AppleTransactionPayload>(transactionJWS, dependencies.appleJWSOptions)
      : undefined;
    const renewal = renewalJWS
      ? dependencies.verifyRenewalInfo
        ? await dependencies.verifyRenewalInfo(renewalJWS)
        : await verifyAppleJWS<AppleRenewalInfoPayload>(renewalJWS, dependencies.appleJWSOptions)
      : undefined;

    if (transaction && !validTransaction(transaction, env)) return jsonResponse({ error: "invalid transaction" }, 400);
    if (renewal && (!PRODUCT_IDS.has(renewal.productId ?? "")
      || typeof renewal.originalTransactionId !== "string"
      || renewal.originalTransactionId.length === 0
      || (renewal.environment !== "Production" && renewal.environment !== "Sandbox"))) {
      return jsonResponse({ error: "invalid renewal" }, 400);
    }
    if (notification.data?.environment && transaction && notification.data.environment !== transaction.environment) {
      return jsonResponse({ error: "notification environment mismatch" }, 400);
    }
    if (notification.data?.environment && renewal && notification.data.environment !== renewal.environment) {
      return jsonResponse({ error: "notification environment mismatch" }, 400);
    }
    if (transaction && renewal && transaction.originalTransactionId !== renewal.originalTransactionId) {
      return jsonResponse({ error: "notification transaction mismatch" }, 400);
    }
    if (transaction && renewal && renewal.productId && transaction.productId !== renewal.productId) {
      return jsonResponse({ error: "notification product mismatch" }, 400);
    }
    await processAppleNotification(env, notification, transaction, renewal, dependencies.now?.() ?? Date.now());
    await env.AUTH.put(notificationKey(notification.notificationUUID), "1", { expirationTtl: NOTIFICATION_TTL_SECONDS });
    return jsonResponse({ ok: true });
  } catch {
    return jsonResponse({ error: "notification could not be processed" }, 400);
  }
}
