import { SignJWT, importPKCS8 } from "jose";
import type { Env } from "./auth";
/** Content-free invitation notification. No message text, profile or encounter identifier. */
export async function notify(
  token: string,
  e: Env,
): Promise<"ok" | "invalid" | "unavailable"> {
  if (!e.APNS_KEY_ID || !e.APNS_TEAM_ID || !e.APNS_PRIVATE_KEY)
    return "unavailable";
  try {
    const jwt = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: e.APNS_KEY_ID })
      .setIssuer(e.APNS_TEAM_ID)
      .setIssuedAt()
      .sign(await importPKCS8(e.APNS_PRIVATE_KEY, "ES256"));
    const host =
      e.APNS_ENVIRONMENT === "production"
        ? "api.push.apple.com"
        : "api.sandbox.push.apple.com";
    const res = await fetch(`https://${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": e.APPLE_CLIENT_ID,
        "apns-push-type": "alert",
        "apns-priority": "5",
        "apns-expiration": "0",
        "apns-collapse-id": "airtalk-request",
      },
      body: JSON.stringify({
        aps: {
          alert: { "loc-key": "ONLINE_REQUEST_NOTIFICATION" },
          sound: "default",
        },
      }),
      signal: AbortSignal.timeout(5000),
    });
    return res.ok ? "ok" : res.status === 410 ? "invalid" : "unavailable";
  } catch {
    return "unavailable";
  }
}
