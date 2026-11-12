import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { Model, DAY, type Sql } from "../src/model";
export function memorySql(): Sql {
  const db = new DatabaseSync(":memory:");
  return { exec: (q, ...p) => db.prepare(q).all(...p) as any };
}
function setup() {
  const m = new Model(memorySql(), 1_000_000);
  for (const id of ["a", "b", "c"])
    m.create({
      id,
      subject: id,
      profile: { name: id, intro: "", icon: "person.circle" },
      adult: true,
      consent: true,
      ble: true,
      created: m.now,
    });
  return m;
}
test("requires encounter, recipient approval and only one concurrent room", () => {
  const m = setup();
  assert.throws(() => m.request("a", "b"));
  m.encounter("a", "b");
  const r = m.request("a", "b").request;
  assert.equal(m.request("a", "b").request.id, r.id);
  assert.throws(() => m.start("a", r.id));
  assert.throws(() => m.respond("a", r.id, true));
  m.respond("b", r.id, true);
  const room = m.start("a", r.id);
  assert.throws(() => m.start("b", r.id));
  assert.throws(() => m.room("c", room.id));
});
test("reconnection requires both intents and a new approval", () => {
  const m = setup();
  m.encounter("a", "b");
  const req = m.request("a", "b").request;
  m.respond("b", req.id, true);
  const room = m.start("a", req.id);
  m.reconnect("a", room.id);
  assert.equal(m.count("connections"), 0);
  m.reconnect("b", room.id);
  assert.equal(m.count("connections"), 1);
  m.end(room.id);
  m.now += 2 * DAY;
  m.prune();
  const again = m.request("a", "b").request;
  assert.throws(() => m.start("a", again.id));
  m.respond("b", again.id, true);
  m.start("b", again.id);
});
test("block immediately denies room and later requests; expired encounters cannot request", () => {
  const m = setup();
  m.encounter("a", "b");
  const req = m.request("a", "b").request;
  m.respond("b", req.id, true);
  const room = m.start("a", req.id);
  m.block("b", "a");
  assert.throws(() => m.room("a", room.id));
  assert.throws(() => m.request("a", "b"));
  m.encounter("a", "c");
  m.now += DAY;
  m.prune();
  assert.throws(() => m.request("a", "c"));
});
test("timeout, account deletion and bounded report retention", () => {
  const m = setup();
  m.encounter("a", "b");
  const req = m.request("a", "b").request;
  m.respond("b", req.id, true);
  const room = m.start("a", req.id);
  m.now += 45_000;
  m.prune();
  assert.throws(() => m.room("a", room.id));
  m.addReport({
    by: "b",
    target: "a",
    reason: "spam",
    until: m.now + 90 * DAY,
  });
  m.remove("a");
  assert.throws(() => m.account("a"));
  assert.equal(m.count("encounters"), 0);
  assert.equal(m.count("requests"), 0);
  assert.equal(m.reports().length, 1);
  m.now += 90 * DAY;
  m.prune();
  assert.equal(m.reports().length, 0);
});

import { permittedMessage } from "../src/content-policy";
test("pilot filter rejects links, contact harvesting, repetitive spam and explicit threats", () => {
  assert.equal(permittedMessage("今日はどんな本を読んだ？"), true);
  assert.equal(permittedMessage("Visit HTTPS://example.com"), false);
  assert.equal(permittedMessage("Contact example@example.com"), false);
  assert.equal(permittedMessage("a".repeat(30)), false);
  assert.equal(permittedMessage("kill yourself"), false);
});

test("legacy single-value snapshot migrates into tables, keeping sign-ins and safety records", () => {
  const m = new Model(memorySql(), 1_000_000);
  const acct = (id: string) => ({
    id,
    subject: `apple-${id}`,
    profile: { name: id, intro: "hi", icon: "leaf.fill" },
    adult: true,
    consent: true,
    ble: true,
    created: 1,
    apple: "encrypted",
    appleChecked: 2,
    push: "a".repeat(64),
    key: { kty: "EC", crv: "P-256", x: "x", y: "y" },
  });
  m.importSnapshot({
    accounts: { a: acct("a"), b: { ...acct("b"), disabled: true } },
    sessions: {
      h: {
        account: "a",
        access: "h",
        refresh: "r",
        accessUntil: 2_000_000,
        refreshUntil: 9_000_000,
      },
    },
    encounters: { "a:b": { a: "a", b: "b", until: 1_500_000 } },
    connections: { "a:b": { a: "a", b: "b", until: 0 } },
    requests: {
      q: { id: "q", from: "a", to: "b", status: "pending", until: 1_500_000 },
    },
    blocks: { "b:a": { from: "b", to: "a" } },
    reports: [{ by: "b", target: "a", reason: "spam", until: 5_000_000 }],
    bans: { k: 9_000_000 },
    deletions: { z: { apple: "enc", until: 9_000_000 } },
  });
  assert.deepEqual(m.find("a"), acct("a"));
  assert.equal(m.find("b")?.disabled, true);
  assert.equal(m.session("h")?.account, "a");
  assert.equal(m.sessionByRefresh("r")?.access, "h");
  assert.equal(m.encounterUntil("b", "a"), 1_500_000);
  assert.equal(m.connected("a", "b"), true);
  assert.equal(m.requestsOf("b")[0].from, "a");
  assert.equal(m.blocked("a", "b"), true);
  assert.equal(m.reports().length, 1);
  assert.equal(m.banned("k"), true);
  assert.equal(m.deletions(5)[0].account, "z");
});

test("account changes are written back once and only when they change", () => {
  const writes: string[] = [];
  const base = memorySql();
  const m = new Model({
    exec: (q, ...p) => (
      q.startsWith("INSERT INTO accounts") && writes.push(q),
      base.exec(q, ...p)
    ),
  });
  m.create({
    id: "a",
    subject: "a",
    profile: { name: "a", intro: "", icon: "person.circle" },
    adult: true,
    consent: true,
    ble: false,
    created: 0,
  });
  m.begin(1);
  m.account("a");
  m.flush();
  assert.equal(writes.length, 1);
  m.account("a").push = "b".repeat(64);
  m.flush();
  assert.equal(writes.length, 2);
  m.begin(2);
  assert.equal(m.account("a").push, "b".repeat(64));
});

test("per-request work stays small with many accounts", () => {
  const m = new Model(memorySql(), 1_000_000);
  const N = 20_000;
  for (let i = 0; i < N; i++)
    m.create({
      id: `u${i}`,
      subject: `s${i}`,
      profile: { name: `u${i}`, intro: "", icon: "person.circle" },
      adult: true,
      consent: true,
      ble: true,
      created: 0,
    });
  for (let i = 0; i < N; i++) m.encounter(`u${i}`, `u${(i + 1) % N}`);
  const started = performance.now();
  for (let i = 0; i < 1000; i++) {
    const id = `u${(i * 7919) % N}`;
    m.begin(1_000_000);
    m.account(id);
    m.encountersOf(id);
    m.requestsOf(id);
    m.connectionsOf(id);
    m.roomsOf(id);
    m.flush();
  }
  const perRequest = (performance.now() - started) / 1000;
  assert.ok(perRequest < 2, `per-request ${perRequest.toFixed(3)}ms`);
  assert.equal(m.encountersOf("u0").length, 2);
});
