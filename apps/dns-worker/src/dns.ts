const DNS_HEADER_SIZE = 12;
const MAX_LABEL_LENGTH = 63;
const MAX_NAME_LENGTH = 253;
const MAX_RECORDS = 4096;
const MAX_TTL = 86400;
export const BLOCKED_RESPONSE_TTL = 60;

export interface DNSQuestion {
  name: string;
  type: number;
  klass: number;
  raw: Uint8Array;
}

export interface DNSRecord {
  type: number;
  ttl: number;
  ttlOffset: number;
  raw: Uint8Array;
}

export interface ParsedDNSMessage {
  id: number;
  flags: number;
  questions: DNSQuestion[];
  records: DNSRecord[];
  additionals: Uint8Array[];
}

export class DNSFormatError extends Error {}

function u16(data: Uint8Array, offset: number): number {
  if (offset + 2 > data.length) throw new DNSFormatError("short dns field");
  return (data[offset] << 8) | data[offset + 1];
}

function u32(data: Uint8Array, offset: number): number {
  if (offset + 4 > data.length) throw new DNSFormatError("short dns ttl");
  return ((data[offset] * 0x1000000) + (data[offset + 1] << 16) + (data[offset + 2] << 8) + data[offset + 3]) >>> 0;
}

function readName(data: Uint8Array, start: number): { name: string; next: number } {
  let offset = start;
  let next = start;
  let jumped = false;
  const labels: string[] = [];
  const visited = new Set<number>();
  while (true) {
    if (offset >= data.length) throw new DNSFormatError("short dns name");
    const length = data[offset];
    if (length === 0) {
      if (!jumped) next = offset + 1;
      break;
    }
    if ((length & 0xc0) === 0xc0) {
      if (offset + 1 >= data.length) throw new DNSFormatError("short dns pointer");
      const pointer = ((length & 0x3f) << 8) | data[offset + 1];
      if (visited.has(pointer) || pointer >= data.length) throw new DNSFormatError("invalid dns pointer");
      visited.add(pointer);
      if (!jumped) next = offset + 2;
      offset = pointer;
      jumped = true;
      if (visited.size > 128) throw new DNSFormatError("dns pointer loop");
      continue;
    }
    if ((length & 0xc0) !== 0 || length > MAX_LABEL_LENGTH || offset + 1 + length > data.length) {
      throw new DNSFormatError("invalid dns label");
    }
    const labelBytes = data.subarray(offset + 1, offset + 1 + length);
    let label = "";
    for (const byte of labelBytes) {
      if (byte < 0x21 || byte > 0x7e) throw new DNSFormatError("non printable dns label");
      label += String.fromCharCode(byte).toLowerCase();
    }
    labels.push(label);
    if (labels.join(".").length + labels.length - 1 > MAX_NAME_LENGTH) throw new DNSFormatError("dns name too long");
    offset += 1 + length;
    if (!jumped) next = offset;
  }
  return { name: labels.join("."), next };
}

function parseRecord(data: Uint8Array, offset: number): { record: DNSRecord; next: number; isOPT: boolean } {
  const start = offset;
  const name = readName(data, offset);
  offset = name.next;
  const type = u16(data, offset);
  const klass = u16(data, offset + 2);
  const ttl = u32(data, offset + 4);
  const length = u16(data, offset + 8);
  offset += 10;
  if (offset + length > data.length) throw new DNSFormatError("short dns rdata");
  return {
    record: {
      type,
      ttl: Math.min(ttl, MAX_TTL),
      ttlOffset: name.next + 4,
      raw: data.slice(start, offset + length),
    },
    next: offset + length,
    isOPT: type === 41 && klass > 0,
  };
}

export function parseDNSMessage(data: Uint8Array, expectedQR?: 0 | 1): ParsedDNSMessage {
  if (data.length < DNS_HEADER_SIZE || data.length > 65535) throw new DNSFormatError("invalid dns size");
  const id = u16(data, 0);
  const flags = u16(data, 2);
  if (expectedQR !== undefined && ((flags & 0x8000) ? 1 : 0) !== expectedQR) throw new DNSFormatError("unexpected dns qr");
  if ((flags & 0x7800) !== 0) throw new DNSFormatError("unsupported dns opcode");
  const qdCount = u16(data, 4);
  const anCount = u16(data, 6);
  const nsCount = u16(data, 8);
  const arCount = u16(data, 10);
  if (qdCount < 1 || qdCount > 1 || anCount + nsCount + arCount > MAX_RECORDS) throw new DNSFormatError("invalid dns counts");
  let offset = DNS_HEADER_SIZE;
  const questions: DNSQuestion[] = [];
  for (let i = 0; i < qdCount; i += 1) {
    const start = offset;
    const name = readName(data, offset);
    offset = name.next;
    const type = u16(data, offset);
    const klass = u16(data, offset + 2);
    if (type === 0 || klass === 0) throw new DNSFormatError("invalid dns question");
    offset += 4;
    questions.push({ name: name.name, type, klass, raw: data.slice(start, offset) });
  }
  const records: DNSRecord[] = [];
  for (let i = 0; i < anCount + nsCount; i += 1) {
    const parsed = parseRecord(data, offset);
    records.push(parsed.record);
    offset = parsed.next;
  }
  const additionals: Uint8Array[] = [];
  for (let i = 0; i < arCount; i += 1) {
    const parsed = parseRecord(data, offset);
    if (parsed.isOPT) additionals.push(parsed.record.raw);
    records.push(parsed.record);
    offset = parsed.next;
  }
  if (offset !== data.length) throw new DNSFormatError("trailing dns bytes");
  return { id, flags, questions, records, additionals };
}

function header(id: number, flags: number, qd: number, an: number, ns: number, ar: number): Uint8Array {
  return Uint8Array.from([
    id >> 8, id & 0xff, flags >> 8, flags & 0xff, qd >> 8, qd & 0xff,
    an >> 8, an & 0xff, ns >> 8, ns & 0xff, ar >> 8, ar & 0xff,
  ]);
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function answerRecord(type: number): Uint8Array {
  const recordType = type === 1 ? 1 : 28;
  const address = new Uint8Array(type === 1 ? 4 : 16);
  return concat(
    Uint8Array.from([
      0xc0, 0x0c, recordType >> 8, recordType & 0xff, 0, 1,
      0, 0, 0, BLOCKED_RESPONSE_TTL, address.length >> 8, address.length & 0xff,
    ]),
    address,
  );
}

export function formErrorResponse(query: Uint8Array): Uint8Array {
  if (query.length < 2) return new Uint8Array();
  const id = (query[0] << 8) | query[1];
  const flags = 0x8000 | ((query.length >= 4 ? ((query[2] << 8) | query[3]) : 0) & 0x0110) | 0x0001;
  return header(id, flags, 0, 0, 0, 0);
}

export function servfailResponse(query: ParsedDNSMessage): Uint8Array {
  const flags = 0x8000 | (query.flags & 0x0110) | 0x0002;
  return concat(header(query.id, flags, 1, 0, 0, query.additionals.length), query.questions[0].raw, ...query.additionals);
}

export function blockedResponse(query: ParsedDNSMessage): Uint8Array {
  const question = query.questions[0];
  const answer = question.type === 1 || question.type === 28 ? answerRecord(question.type) : new Uint8Array();
  const flags = 0x8080 | (query.flags & 0x0110);
  return concat(header(query.id, flags, 1, answer.length ? 1 : 0, 0, query.additionals.length), question.raw, answer, ...query.additionals);
}

export function withTransactionID(message: Uint8Array, id: number): Uint8Array {
  const result = message.slice();
  result[0] = id >> 8;
  result[1] = id & 0xff;
  return result;
}

export function withRemainingTTL(message: Uint8Array, ttl: number): Uint8Array {
  const result = message.slice();
  const parsed = parseDNSMessage(result, 1);
  const remaining = Math.max(0, Math.min(ttl, MAX_TTL));
  for (const record of parsed.records) {
    if (record.type === 41) continue;
    result[record.ttlOffset] = remaining >>> 24;
    result[record.ttlOffset + 1] = remaining >>> 16;
    result[record.ttlOffset + 2] = remaining >>> 8;
    result[record.ttlOffset + 3] = remaining & 0xff;
  }
  return result;
}

export function cacheKey(query: Uint8Array): string {
  const normalized = query.slice();
  normalized[0] = 0;
  normalized[1] = 0;
  let binary = "";
  for (const byte of normalized) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function minimumTTL(message: ParsedDNSMessage): number | null {
  const cacheableRecords = message.records.filter((record) => record.type !== 41);
  if (cacheableRecords.length === 0) return null;
  return Math.min(...cacheableRecords.map((record) => record.ttl));
}

export function isValidUpstreamResponse(query: ParsedDNSMessage, response: Uint8Array): ParsedDNSMessage {
  const parsed = parseDNSMessage(response, 1);
  const expected = query.questions[0];
  const actual = parsed.questions[0];
  if (parsed.id !== query.id || actual.name !== expected.name || actual.type !== expected.type || actual.klass !== expected.klass) {
    throw new DNSFormatError("upstream response does not match query");
  }
  return parsed;
}
