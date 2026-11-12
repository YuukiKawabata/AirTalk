import { createRemoteJWKSet, jwtVerify, SignJWT, importPKCS8 } from "jose";
import { Fault, requireThat } from "./model";
export interface Env {
  PILOT: DurableObjectNamespace;
  MODE: string;
  ONLINE_ENABLED: string;
  APPLE_CLIENT_ID: string;
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  TOKEN_ENCRYPTION_KEY?: string;
  MAX_ACCOUNTS?: string;
  GLOBAL_DAILY_LIMIT?: string;
  ADMIN_TOKEN?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_ENVIRONMENT?: string;
}
const encoder = new TextEncoder();
export const b64 = (data: Uint8Array) =>
  btoa(String.fromCharCode(...data))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
export const unb64 = (s: string) =>
  Uint8Array.from(atob(s.replaceAll("-", "+").replaceAll("_", "/")), (c) =>
    c.charCodeAt(0),
  );
export const random = () => b64(crypto.getRandomValues(new Uint8Array(32)));
export const hash = async (s: string) =>
  b64(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(s))));
const keys = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
  { timeoutDuration: 5000 },
);
export async function clientSecret(e: Env) {
  requireThat(
    e.APPLE_PRIVATE_KEY && e.APPLE_KEY_ID && e.APPLE_TEAM_ID,
    "service_not_configured",
    503,
  );
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: e.APPLE_KEY_ID })
    .setIssuer(e.APPLE_TEAM_ID)
    .setAudience("https://appleid.apple.com")
    .setSubject(e.APPLE_CLIENT_ID)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(await importPKCS8(e.APPLE_PRIVATE_KEY, "ES256"));
}
async function applePost(path: string, params: Record<string, string>, e: Env) {
  const res = await fetch(`https://appleid.apple.com/auth/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      ...params,
      client_id: e.APPLE_CLIENT_ID,
      client_secret: await clientSecret(e),
    }),
    signal: AbortSignal.timeout(8000),
  });
  requireThat(res.ok, "apple_auth_failed", 401);
  return res;
}
export async function appleLogin(
  code: string,
  token: string,
  nonce: string,
  e: Env,
) {
  const check = async (t: string) => {
    const { payload } = await jwtVerify(t, keys, {
      issuer: "https://appleid.apple.com",
      audience: e.APPLE_CLIENT_ID,
      algorithms: ["RS256"],
    }).catch(() => {
      throw new Fault("apple_auth_failed", 401);
    });
    requireThat(
      payload.sub && payload.nonce === nonce,
      "apple_auth_failed",
      401,
    );
    return payload.sub;
  };
  const sub = await check(token);
  const result = (await (
    await applePost("token", { code, grant_type: "authorization_code" }, e)
  ).json()) as { id_token: string; refresh_token: string };
  requireThat(
    result.id_token &&
      result.refresh_token &&
      (await check(result.id_token)) === sub,
    "apple_auth_failed",
    401,
  );
  return { sub, refresh: await seal(result.refresh_token, e) };
}
export async function appleRefresh(encrypted: string, e: Env) {
  await applePost(
    "token",
    { refresh_token: await open(encrypted, e), grant_type: "refresh_token" },
    e,
  );
}
export async function revoke(encrypted: string, e: Env) {
  await applePost(
    "revoke",
    { token: await open(encrypted, e), token_type_hint: "refresh_token" },
    e,
  );
}
async function aes(e: Env) {
  requireThat(e.TOKEN_ENCRYPTION_KEY, "service_not_configured", 503);
  const bytes = unb64(e.TOKEN_ENCRYPTION_KEY);
  requireThat(bytes.length === 32, "service_not_configured", 503);
  return crypto.subtle.importKey("raw", bytes, { name: "AES-GCM" }, false, [
    "encrypt",
    "decrypt",
  ]);
}
async function seal(value: string, e: Env) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await aes(e),
    encoder.encode(value),
  );
  return `${b64(iv)}.${b64(new Uint8Array(cipher))}`;
}
async function open(value: string, e: Env) {
  const [iv, data] = value.split(".");
  return new TextDecoder().decode(
    await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: unb64(iv) },
      await aes(e),
      unb64(data),
    ),
  );
}
export async function verifyReceipt(
  key: JsonWebKey,
  payload: string,
  signature: string,
) {
  try {
    const k = await crypto.subtle.importKey(
      "jwk",
      key,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    return await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      k,
      unb64(signature),
      encoder.encode(payload),
    );
  } catch {
    return false;
  }
}
