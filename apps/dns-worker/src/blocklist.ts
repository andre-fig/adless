const DOMAIN_LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
const RESERVED = new Set([
  "localhost",
  "localhost.localdomain",
  "broadcasthost",
  "ip6-allnodes",
  "ip6-allrouters",
  "ip6-localhost",
]);

export function normalizeDomain(value: string): string | null {
  let candidate = value.trim();
  if (candidate.endsWith(".")) candidate = candidate.slice(0, -1);
  if (!candidate || candidate.endsWith(".") || candidate.startsWith(".") || candidate.includes("..")) return null;
  if (["/", "|", "^", ":", "@", "?", "#", "*"].some((character) => candidate.includes(character))) return null;

  let normalized: string;
  try {
    normalized = new URL(`https://${candidate}`).hostname.toLowerCase().replace(/\.$/, "");
  } catch {
    return null;
  }

  if (!normalized || normalized.length > 253 || RESERVED.has(normalized)) return null;
  if (!normalized.includes(".")) return null;
  const labels = normalized.split(".");
  if (labels.some((label) => label.length > 63 || !DOMAIN_LABEL.test(label))) return null;
  return normalized;
}

export interface BlocklistMetadata {
  schemaVersion: number;
  version: string;
  domainCount: number;
  textSHA256?: string;
}

export interface Blocklist {
  readonly size: number;
  has(domain: string): boolean;
}

export function createBlocklist(text: string, metadata: BlocklistMetadata): Blocklist {
  if (metadata.schemaVersion !== 1 || !/^v[0-9a-f]{16}$/.test(metadata.version)) {
    throw new Error("invalid blocklist metadata");
  }
  if (!Number.isInteger(metadata.domainCount) || metadata.domainCount < 1 || metadata.domainCount > 200_000) {
    throw new Error("invalid blocklist count");
  }
  if (!text.endsWith("\n")) throw new Error("blocklist is not canonical");
  const entries = text.split("\n").filter(Boolean);
  if (entries.length !== metadata.domainCount) throw new Error("blocklist count mismatch");
  const exact = new Set<string>();
  let previous = "";
  for (const entry of entries) {
    if (entry <= previous || normalizeDomain(entry) !== entry) throw new Error("blocklist is not sorted and canonical");
    previous = entry;
    exact.add(entry);
  }
  return {
    size: exact.size,
    has(domain: string): boolean {
      const normalized = normalizeDomain(domain);
      if (!normalized) return false;
      const labels = normalized.split(".");
      for (let index = 0; index < labels.length; index += 1) {
        if (exact.has(labels.slice(index).join("."))) return true;
      }
      return false;
    },
  };
}
