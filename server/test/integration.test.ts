import test from "node:test";
import assert from "node:assert/strict";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";
import { webcrypto, randomUUID } from "node:crypto";
const make = (mode = "local", enabled = "true") =>
  new Miniflare({
    ...convertV4MiniflareOptions({
      name: "airtalk-test",
      modules: true,
      scriptPath: "dist/index.js",
      compatibilityDate: "2026-01-01",
      durableObjects: { PILOT: { className: "PilotHub", useSQLite: true } },
      bindings: {
        MODE: mode,
        ONLINE_ENABLED: enabled,
        APPLE_CLIENT_ID: "com.yuuki.AirTalk",
        ADMIN_TOKEN: "local-test-administration-secret-0123456789",
      },
    }),
    unsafeInspectDurableObjects: true,
  });
async function call(
  mf: Miniflare,
  path: string,
  token?: string,
  body?: any,
  method = body ? "POST" : "GET",
) {
  const res = await mf.dispatchFetch(`http://localhost${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: (await res.json()) as any };
}
async function login(mf: Miniflare, name: string) {
  const r = await call(mf, "/v1/dev/login", undefined, { name });
  assert.equal(r.status, 200);
  return r.data;
}
async function socket(mf: Miniflare, session: any, room: string) {
  const ticket = await call(
    mf,
    `/v1/conversations/${room}/ticket`,
    session.accessToken,
    {},
  );
  assert.equal(ticket.status, 200);
  const res = await mf.dispatchFetch(
    `http://localhost/v1/conversations/${room}/socket`,
    {
      headers: {
        Upgrade: "websocket",
        Authorization: `Bearer ${session.accessToken}`,
        "X-AirTalk-Ticket": ticket.data.ticket,
      },
    },
  );
  assert.equal(res.status, 101);
  res.webSocket!.accept();
  return res.webSocket!;
}
function next(ws: any) {
  return new Promise<any>((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("websocket timeout")),
      3000,
    );
    const handler = (event: any) => {
      const value = JSON.parse(event.data);
      if (value.type === "ready") return;
      clearTimeout(timeout);
      ws.removeEventListener("message", handler);
      resolve(value);
    };
    ws.addEventListener("message", handler);
  });
}
test("real worker: mutual approval, relay, report/block and deletion", async () => {
  const mf = make();
  try {
    const a = await login(mf, "A"),
      b = await login(mf, "B"),
      c = await login(mf, "C");
    assert.equal(
      (await call(mf, "/v1/requests", a.accessToken, { peerID: b.accountID }))
        .status,
      403,
    );
    assert.equal(
      (
        await call(mf, "/v1/dev/encounter", a.accessToken, {
          peerID: b.accountID,
        })
      ).status,
      200,
    );
    const req = (
      await call(mf, "/v1/requests", a.accessToken, { peerID: b.accountID })
    ).data;
    assert.equal(
      (await call(mf, `/v1/requests/${req.id}/accept`, c.accessToken, {}))
        .status,
      404,
    );
    assert.equal(
      (
        await call(mf, "/v1/conversations", a.accessToken, {
          requestID: req.id,
        })
      ).status,
      403,
    );
    assert.equal(
      (await call(mf, `/v1/requests/${req.id}/accept`, b.accessToken, {}))
        .status,
      200,
    );
    const room = (
      await call(mf, "/v1/conversations", a.accessToken, { requestID: req.id })
    ).data.id;
    const wa = await socket(mf, a, room),
      wb = await socket(mf, b, room);
    const msg = next(wb),
      ack = next(wa);
    const messageID = randomUUID();
    wa.send(
      JSON.stringify({
        v: 1,
        conversationID: room,
        type: "message",
        id: messageID,
        text: "memory-only test message",
        sender: c.accountID,
      }),
    );
    assert.deepEqual(await msg, {
      type: "message",
      id: messageID,
      text: "memory-only test message",
      sender: a.accountID,
    });
    assert.equal((await ack).type, "relayed");
    await mf.unsafeEvictDurableObject("airtalk-test", "PilotHub", {
      name: "pilot-v1",
      webSockets: "hibernate",
    });
    const afterWake = next(wb),
      wakeAck = next(wa);
    wa.send(
      JSON.stringify({
        v: 1,
        conversationID: room,
        type: "message",
        id: randomUUID(),
        text: "after hibernation",
      }),
    );
    assert.equal((await afterWake).text, "after hibernation");
    await wakeAck;
    const rejection = next(wa);
    wa.send(
      JSON.stringify({
        v: 1,
        conversationID: room,
        type: "message",
        id: randomUUID(),
        text: "https://example.com",
      }),
    );
    assert.equal((await rejection).type, "rejected");

    await call(
      mf,
      `/v1/conversations/${room}/reconnect-intent`,
      a.accessToken,
      {},
    );
    assert.equal(
      (await call(mf, "/v1/connections", a.accessToken)).data.people.length,
      0,
    );
    await call(
      mf,
      `/v1/conversations/${room}/reconnect-intent`,
      b.accessToken,
      {},
    );
    assert.equal(
      (await call(mf, "/v1/connections", a.accessToken)).data.people.length,
      1,
    );
    const closed = new Promise<void>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("block did not close socket")),
        3000,
      );
      wa.addEventListener(
        "close",
        () => {
          clearTimeout(timer);
          resolve();
        },
        { once: true },
      );
    });
    assert.equal(
      (
        await call(mf, "/v1/reports", b.accessToken, {
          peerID: a.accountID,
          reason: "spam",
        })
      ).status,
      200,
    );
    await closed;
    assert.equal(
      (await call(mf, "/v1/requests", a.accessToken, { peerID: b.accountID }))
        .status,
      403,
    );
    assert.equal(
      (await call(mf, "/v1/connections", a.accessToken)).data.people.length,
      0,
    );
    assert.equal(
      (await call(mf, "/v1/me", a.accessToken, undefined, "DELETE")).status,
      200,
    );
    assert.equal((await call(mf, "/v1/me/profile", a.accessToken)).status, 401);
    assert.equal(
      (
        await call(mf, "/v1/auth/refresh", undefined, {
          refreshToken: a.refreshToken,
        })
      ).status,
      401,
    );
  } finally {
    await mf.dispose();
  }
});
test("production cannot use local auth and kill switch fails closed", async () => {
  const mf = make("production");
  try {
    assert.equal(
      (await call(mf, "/v1/dev/login", undefined, { name: "attacker" })).status,
      404,
    );
    assert.equal((await call(mf, "/v1/me/profile")).status, 401);
  } finally {
    await mf.dispose();
  }
  const off = make("production", "false");
  try {
    assert.equal((await call(off, "/health")).status, 503);
  } finally {
    await off.dispose();
  }
});
test("signed encounters reject unilateral, modified and foreign receipts", async () => {
  const mf = make();
  try {
    const a = await login(mf, "A"),
      b = await login(mf, "B"),
      c = await login(mf, "C");
    const create = async (s: any) => {
      const keys = await webcrypto.subtle.generateKey(
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["sign", "verify"],
      );
      const key = await webcrypto.subtle.exportKey("jwk", keys.publicKey);
      await call(
        mf,
        "/v1/me/consents",
        s.accessToken,
        { adult: true, consent: true, ble: true, version: "pilot-1" },
        "PUT",
      );
      assert.equal(
        (await call(mf, "/v1/me/device", s.accessToken, { key }, "PUT")).status,
        200,
      );
      return {
        keys,
        token: (await call(mf, "/v1/encounter-tokens", s.accessToken, {})).data
          .token,
      };
    };
    const ka = await create(a),
      kb = await create(b);
    const receipt = {
      tokenA: ka.token,
      tokenB: kb.token,
      challengeA: Buffer.from(
        webcrypto.getRandomValues(new Uint8Array(32)),
      ).toString("base64url"),
      challengeB: Buffer.from(
        webcrypto.getRandomValues(new Uint8Array(32)),
      ).toString("base64url"),
      signatureA: "",
      signatureB: "",
    };
    const payload = new TextEncoder().encode(
      [
        "airtalk-encounter-v1",
        receipt.tokenA,
        receipt.tokenB,
        receipt.challengeA,
        receipt.challengeB,
      ].join("\n"),
    );
    receipt.signatureA = Buffer.from(
      await webcrypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        ka.keys.privateKey,
        payload,
      ),
    ).toString("base64url");
    assert.notEqual(
      (await call(mf, "/v1/encounter-receipts", a.accessToken, receipt)).status,
      200,
    );
    receipt.signatureB = Buffer.from(
      await webcrypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        kb.keys.privateKey,
        payload,
      ),
    ).toString("base64url");
    assert.equal(
      (await call(mf, "/v1/encounter-receipts", c.accessToken, receipt)).status,
      403,
    );
    assert.equal(
      (
        await call(mf, "/v1/encounter-receipts", a.accessToken, {
          ...receipt,
          challengeA: receipt.challengeB,
        })
      ).status,
      403,
    );
    assert.equal(
      (await call(mf, "/v1/encounter-receipts", a.accessToken, receipt)).status,
      200,
    );
    assert.equal(
      (await call(mf, "/v1/encounter-receipts", b.accessToken, receipt)).status,
      200,
    );
    assert.equal(
      (await call(mf, "/v1/encounters", a.accessToken)).data.people.length,
      1,
    );
  } finally {
    await mf.dispose();
  }
});

test("moderator auth, suspension and suspended-account deletion", async () => {
  const mf = make();
  try {
    const a = await login(mf, "A");
    assert.equal((await call(mf, "/admin/reports", a.accessToken)).status, 401);
    const admin = "local-test-administration-secret-0123456789";
    assert.equal(
      (await call(mf, "/admin/suspend", admin, { accountID: a.accountID }))
        .status,
      200,
    );
    assert.equal((await call(mf, "/v1/encounters", a.accessToken)).status, 401);
    const target = { accountID: a.accountID };
    assert.equal((await call(mf, "/admin/restore", a.accessToken, target)).status, 401);
    assert.equal((await call(mf, "/admin/restore", admin, target)).status, 200);
    assert.equal((await call(mf, "/v1/encounters", a.accessToken)).status, 200);
    assert.equal((await call(mf, "/admin/suspend", admin, target)).status, 200);

    assert.equal(
      (await call(mf, "/v1/me", a.accessToken, undefined, "DELETE")).status,
      200,
    );
  } finally {
    await mf.dispose();
  }
});
