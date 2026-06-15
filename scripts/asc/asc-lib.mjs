// App Store Connect API の最小ヘルパー（外部依存なし・Node 標準のみ）。
// 認証情報はアカウント共通の ~/.appstoreconnect/asc.env から読む。
import { readFileSync } from "node:fs";
import { createSign } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";

const ENV_PATH = join(homedir(), ".appstoreconnect", "asc.env");

function loadEnv() {
  const env = {};
  for (const line of readFileSync(ENV_PATH, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.+?)\s*$/);
    if (m && !line.trimStart().startsWith("#")) env[m[1]] = m[2];
  }
  return env;
}

const b64url = (buf) =>
  Buffer.from(buf).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

// ES256 で署名した ASC 用 JWT を作る（有効期限 ~15 分）
export function makeToken() {
  const env = loadEnv();
  const key = readFileSync(env.ASC_KEY_PATH, "utf8");
  const header = { alg: "ES256", kid: env.ASC_KEY_ID, typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: env.ASC_ISSUER_ID,
    iat: now,
    exp: now + 15 * 60,
    aud: "appstoreconnect-v1",
  };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const signer = createSign("SHA256");
  signer.update(signingInput);
  // ASC は JOSE 形式（r||s）の署名を要求するので dsaEncoding を ieee-p1363 にする
  const sig = signer.sign({ key, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${b64url(sig)}`;
}

const BASE = "https://api.appstoreconnect.apple.com";

// ASC API を叩く。path は "/v1/..." 形式。
export async function asc(path, { method = "GET", body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      Authorization: `Bearer ${makeToken()}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  if (!res.ok) {
    const err = new Error(`ASC ${method} ${path} -> ${res.status}`);
    err.status = res.status;
    err.body = json;
    throw err;
  }
  return json;
}
