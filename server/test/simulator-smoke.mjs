// Local-only native URLSession/WebSocket smoke test; no Apple credentials.
import { execFileSync as run } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { randomUUID } from "node:crypto";
import WebSocket from "ws";
const udid = process.env.SIMULATOR_UDID,
  app = process.env.AIRTALK_SIM_APP;
if (!udid || !app) throw Error("Set SIMULATOR_UDID and AIRTALK_SIM_APP");
const call = async (p, token, body, method = body ? "POST" : "GET") => {
  const r = await fetch(`http://127.0.0.1:8787${p}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await r.json();
  if (!r.ok) throw Error(`${p}: ${r.status} ${data.code}`);
  return data;
};
let ws;
try {
  const a = await call("/v1/dev/login", null, { name: "Simulator Alice" }),
    b = await call("/v1/dev/login", null, { name: "Simulator Bob" });
  await call("/v1/dev/encounter", a.accessToken, { peerID: b.accountID });
  const req = await call("/v1/requests", a.accessToken, {
    peerID: b.accountID,
  });
  await call(`/v1/requests/${req.id}/accept`, b.accessToken, {});
  run("xcrun", ["simctl", "install", udid, app]);
  try {
    run("xcrun", ["simctl", "terminate", udid, "com.yuuki.AirTalk"], {
      stdio: "ignore",
    });
  } catch {}
  run("xcrun", [
    "simctl",
    "launch",
    udid,
    "com.yuuki.AirTalk",
    "-demo",
    "NO",
    "-onlineURL",
    "http://127.0.0.1:8787",
    "-onlinePilot",
    "YES",
    "-onlineTestName",
    "Simulator Alice",
    "-onlineTestJoin",
    "YES",
    "-AppleLanguages",
    "(ja)",
    "-AppleLocale",
    "ja_JP",
  ]);
  let room;
  for (let i = 0; i < 40; i++) {
    room = (await call("/v1/conversations", b.accessToken)).rooms[0];
    if (room) break;
    await wait(250);
  }
  if (!room) throw Error("iOS did not create a conversation");
  const { ticket } = await call(
    `/v1/conversations/${room.id}/ticket`,
    b.accessToken,
    {},
  );
  ws = new WebSocket(`ws://127.0.0.1:8787/v1/conversations/${room.id}/socket`, {
    headers: {
      Authorization: `Bearer ${b.accessToken}`,
      "X-AirTalk-Ticket": ticket,
    },
  });
  await new Promise((ok, no) => {
    ws.once("open", ok);
    ws.once("error", no);
  });
  await wait(500);
  const ack = new Promise((ok, no) => {
    const timer = setTimeout(() => no(Error("No relay acknowledgement")), 3000);
    ws.once("message", (data) => {
      clearTimeout(timer);
      JSON.parse(data).type === "relayed"
        ? ok()
        : no(Error("Unexpected frame"));
    });
  });
  ws.send(
    JSON.stringify({
      v: 1,
      conversationID: room.id,
      type: "message",
      id: randomUUID(),
      text: "こんにちは！オンラインでも、また話せてうれしいです。",
    }),
  );
  await ack;
  await wait(1500);
  run("xcrun", [
    "simctl",
    "io",
    udid,
    "screenshot",
    "../docs/screenshots/prototype/online-live-chat-ja.png",
  ]);
  await call("/v1/blocks", b.accessToken, { peerID: a.accountID });
  await wait(1500);
  run("xcrun", [
    "simctl",
    "io",
    udid,
    "screenshot",
    "../docs/screenshots/prototype/online-live-ended-ja.png",
  ]);
  console.log(
    "PASS: iOS login, API start, native WebSocket receive, remote block; screenshots captured",
  );
} finally {
  ws?.close();
  for (const name of ["Simulator Alice", "Simulator Bob"]) {
    try {
      const user = await call("/v1/dev/login", null, { name });
      await call("/v1/me", user.accessToken, null, "DELETE");
    } catch {}
  }
}
