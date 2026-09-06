import "reflect-metadata";
import { X509Certificate } from "@peculiar/x509";
import { compactVerify, decodeProtectedHeader } from "jose";

const APPLE_ROOT_CA_G3_BASE64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

const APPLE_JWS_LEAF_EXTENSION = "1.2.840.113635.100.6.11.1";
const APPLE_JWS_INTERMEDIATE_EXTENSION = "1.2.840.113635.100.6.2.1";

export interface AppleJWSVerificationOptions {
  trustedRootCertificate?: Uint8Array;
  /** SHA-256 of the single Xcode StoreKit Test signing certificate, in hex. */
  trustedLeafCertificateSHA256?: string;
  verificationTime?: Date;
}

export class AppleJWSVerificationError extends Error {
  constructor() {
    super("Apple signed data could not be verified");
    this.name = "AppleJWSVerificationError";
  }
}

function decodeBase64(value: string): Uint8Array {
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw new AppleJWSVerificationError();
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function decodeJSON<T>(value: Uint8Array): T {
  try {
    const decoded: unknown = JSON.parse(new TextDecoder().decode(value));
    if (!decoded || typeof decoded !== "object") throw new AppleJWSVerificationError();
    return decoded as T;
  } catch {
    throw new AppleJWSVerificationError();
  }
}

async function sameCertificate(left: X509Certificate, right: X509Certificate): Promise<boolean> {
  const leftThumbprint = new Uint8Array(await left.getThumbprint("SHA-256"));
  const rightThumbprint = new Uint8Array(await right.getThumbprint("SHA-256"));
  return leftThumbprint.length === rightThumbprint.length
    && leftThumbprint.every((value, index) => value === rightThumbprint[index]);
}

function normalizedSHA256(value: string | undefined): string | undefined {
  const normalized = value?.trim().toLowerCase().replace(/:/g, "");
  return normalized && /^[0-9a-f]{64}$/.test(normalized) ? normalized : undefined;
}

async function certificateSHA256(certificate: X509Certificate): Promise<string> {
  const thumbprint = new Uint8Array(await certificate.getThumbprint("SHA-256"));
  return Array.from(thumbprint, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function verifyCertificateChain(header: Record<string, unknown>, options: AppleJWSVerificationOptions): Promise<CryptoKey> {
  const chain = header.x5c;
  if (!Array.isArray(chain) || chain.some((item) => typeof item !== "string")) {
    throw new AppleJWSVerificationError();
  }

  try {
    const pinnedLeafSHA256 = normalizedSHA256(options.trustedLeafCertificateSHA256);
    if (chain.length === 1 && pinnedLeafSHA256) {
      const leaf = new X509Certificate(decodeBase64(chain[0] as string).buffer as ArrayBuffer);
      const verificationTime = options.verificationTime ?? new Date();
      if (verificationTime < leaf.notBefore
        || verificationTime > leaf.notAfter
        || await certificateSHA256(leaf) !== pinnedLeafSHA256) {
        throw new AppleJWSVerificationError();
      }
      return await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
    }
    if (chain.length !== 3) throw new AppleJWSVerificationError();

    const leaf = new X509Certificate(decodeBase64(chain[0] as string).buffer as ArrayBuffer);
    const intermediate = new X509Certificate(decodeBase64(chain[1] as string).buffer as ArrayBuffer);
    const suppliedRoot = new X509Certificate(decodeBase64(chain[2] as string).buffer as ArrayBuffer);
    const trustedRoot = new X509Certificate((options.trustedRootCertificate ?? decodeBase64(APPLE_ROOT_CA_G3_BASE64)).buffer as ArrayBuffer);
    const verificationTime = options.verificationTime ?? new Date();
    for (const certificate of [leaf, intermediate, suppliedRoot, trustedRoot]) {
      if (verificationTime < certificate.notBefore || verificationTime > certificate.notAfter) {
        throw new AppleJWSVerificationError();
      }
    }

    if (!(await sameCertificate(suppliedRoot, trustedRoot))
      || leaf.issuer !== intermediate.subject
      || intermediate.issuer !== trustedRoot.subject
      || !leaf.getExtension(APPLE_JWS_LEAF_EXTENSION)
      || !intermediate.getExtension(APPLE_JWS_INTERMEDIATE_EXTENSION)
      || !(await intermediate.verify({ publicKey: trustedRoot.publicKey }))
      || !(await leaf.verify({ publicKey: intermediate.publicKey }))) {
      throw new AppleJWSVerificationError();
    }

    return await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
  } catch (error) {
    if (error instanceof AppleJWSVerificationError) throw error;
    throw new AppleJWSVerificationError();
  }
}

export async function verifyAppleJWS<T extends object>(
  value: string,
  options: AppleJWSVerificationOptions = {},
): Promise<T> {
  if (value.length === 0 || value.length > 128 * 1024) throw new AppleJWSVerificationError();
  const parts = value.split(".");
  if (parts.length !== 3 || parts.some((part) => !/^[A-Za-z0-9_-]+$/.test(part))) {
    throw new AppleJWSVerificationError();
  }

  let header: Record<string, unknown>;
  try {
    header = decodeProtectedHeader(value) as Record<string, unknown>;
  } catch {
    throw new AppleJWSVerificationError();
  }
  if (header.alg !== "ES256") throw new AppleJWSVerificationError();

  const publicKey = await verifyCertificateChain(header, options);
  try {
    const result = await compactVerify(value, publicKey, { algorithms: ["ES256"] });
    return decodeJSON<T>(result.payload);
  } catch {
    throw new AppleJWSVerificationError();
  }
}
