export const DAY = 86_400_000;
export const HOUR = 3_600_000;
export class Fault extends Error {
  constructor(
    public code: string,
    public status = 400,
  ) {
    super(code);
  }
}
export function requireThat(
  value: unknown,
  code: string,
  status = 400,
): asserts value {
  if (!value) throw new Fault(code, status);
}
export const uid = () => crypto.randomUUID();
export const pair = (a: string, b: string) => [a, b].sort().join(":");
export interface Profile {
  name: string;
  intro: string;
  icon: string;
}
export interface Account {
  id: string;
  subject: string;
  profile: Profile;
  adult: boolean;
  consent: boolean;
  ble: boolean;
  created: number;
  disabled?: boolean;
  apple?: string;
  appleChecked?: number;
  push?: string;
  key?: JsonWebKey;
}
export interface Session {
  account: string;
  access: string;
  refresh: string;
  accessUntil: number;
  refreshUntil: number;
}
export interface Encounter {
  a: string;
  b: string;
  until: number;
}
export interface RequestRecord {
  id: string;
  from: string;
  to: string;
  status: "pending" | "accepted" | "declined" | "used";
  until: number;
}
export interface Room {
  id: string;
  a: string;
  b: string;
  ended: boolean;
  created: number;
  intents: string[];
  beats: Record<string, number>;
}
export interface Report {
  by: string;
  target: string;
  reason: string;
  until: number;
}
/** Legacy single-value snapshot (pilot storage before SQL tables). Only read once for migration. */
export interface Snapshot {
  accounts: Record<string, Account>;
  sessions: Record<string, Session>;
  encounters: Record<string, Encounter>;
  requests: Record<string, RequestRecord>;
  rooms: Record<string, Room>;
  connections: Record<string, Encounter>;
  blocks: Record<string, { from: string; to: string }>;
  reports: Report[];
  tokens: Record<string, { account: string; until: number }>;
  receipts: Record<string, number>;
  challenges: Record<string, { nonce: string; until: number }>;
  tickets: Record<string, { account: string; room: string; until: number }>;
  rates: Record<string, { n: number; until: number }>;
  deletions: Record<string, { apple: string; until: number }>;
  bans: Record<string, number>;
}

export type SqlValue = string | number | null;
export type Row = Record<string, SqlValue>;
/** Synchronous SQL, implemented by Durable Object SQLite storage and by node:sqlite in tests. */
export interface Sql {
  exec(query: string, ...params: SqlValue[]): Row[];
}

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, subject TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL, intro TEXT NOT NULL, icon TEXT NOT NULL, adult INTEGER NOT NULL,
    consent INTEGER NOT NULL, ble INTEGER NOT NULL, created INTEGER NOT NULL,
    disabled INTEGER NOT NULL DEFAULT 0, apple TEXT, apple_checked INTEGER, push TEXT, key TEXT)`,
  `CREATE TABLE IF NOT EXISTS sessions(access TEXT PRIMARY KEY, account TEXT NOT NULL,
    refresh TEXT NOT NULL, access_until INTEGER NOT NULL, refresh_until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS sessions_account ON sessions(account)`,
  `CREATE INDEX IF NOT EXISTS sessions_refresh ON sessions(refresh)`,
  `CREATE INDEX IF NOT EXISTS sessions_until ON sessions(refresh_until)`,
  `CREATE TABLE IF NOT EXISTS encounters(pair TEXT PRIMARY KEY, a TEXT NOT NULL, b TEXT NOT NULL,
    until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS encounters_a ON encounters(a)`,
  `CREATE INDEX IF NOT EXISTS encounters_b ON encounters(b)`,
  `CREATE INDEX IF NOT EXISTS encounters_until ON encounters(until)`,
  `CREATE TABLE IF NOT EXISTS connections(pair TEXT PRIMARY KEY, a TEXT NOT NULL, b TEXT NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS connections_a ON connections(a)`,
  `CREATE INDEX IF NOT EXISTS connections_b ON connections(b)`,
  `CREATE TABLE IF NOT EXISTS requests(id TEXT PRIMARY KEY, sender TEXT NOT NULL,
    recipient TEXT NOT NULL, pair TEXT NOT NULL, status TEXT NOT NULL, until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS requests_sender ON requests(sender)`,
  `CREATE INDEX IF NOT EXISTS requests_recipient ON requests(recipient)`,
  `CREATE INDEX IF NOT EXISTS requests_pair ON requests(pair)`,
  `CREATE INDEX IF NOT EXISTS requests_until ON requests(until)`,
  `CREATE TABLE IF NOT EXISTS rooms(id TEXT PRIMARY KEY, a TEXT NOT NULL, b TEXT NOT NULL,
    ended INTEGER NOT NULL, created INTEGER NOT NULL, intents TEXT NOT NULL,
    beat_a INTEGER NOT NULL, beat_b INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS rooms_a ON rooms(a)`,
  `CREATE INDEX IF NOT EXISTS rooms_b ON rooms(b)`,
  `CREATE INDEX IF NOT EXISTS rooms_ended ON rooms(ended)`,
  `CREATE TABLE IF NOT EXISTS blocks(blocker TEXT NOT NULL, blocked TEXT NOT NULL,
    PRIMARY KEY(blocker, blocked))`,
  `CREATE INDEX IF NOT EXISTS blocks_blocked ON blocks(blocked)`,
  `CREATE TABLE IF NOT EXISTS reports(id INTEGER PRIMARY KEY AUTOINCREMENT, reporter TEXT NOT NULL,
    target TEXT NOT NULL, reason TEXT NOT NULL, until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS reports_until ON reports(until)`,
  `CREATE TABLE IF NOT EXISTS tokens(hash TEXT PRIMARY KEY, account TEXT NOT NULL, until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS tokens_account ON tokens(account)`,
  `CREATE INDEX IF NOT EXISTS tokens_until ON tokens(until)`,
  `CREATE TABLE IF NOT EXISTS receipts(hash TEXT PRIMARY KEY, until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS receipts_until ON receipts(until)`,
  `CREATE TABLE IF NOT EXISTS challenges(id TEXT PRIMARY KEY, nonce TEXT NOT NULL, until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS challenges_until ON challenges(until)`,
  `CREATE TABLE IF NOT EXISTS tickets(hash TEXT PRIMARY KEY, account TEXT NOT NULL, room TEXT NOT NULL,
    until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS tickets_until ON tickets(until)`,
  `CREATE TABLE IF NOT EXISTS rates(key TEXT PRIMARY KEY, n INTEGER NOT NULL, until INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS rates_until ON rates(until)`,
  `CREATE TABLE IF NOT EXISTS deletions(account TEXT PRIMARY KEY, apple TEXT NOT NULL, until INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS bans(key TEXT PRIMARY KEY, until INTEGER NOT NULL)`,
];
const STALE_BEAT = 45_000;
const num = (v: SqlValue | undefined) => Number(v ?? 0);
const str = (v: SqlValue | undefined) => (v == null ? undefined : String(v));

export class Model {
  /** Accounts loaded during the current operation; flush() writes back the ones that changed. */
  private cache = new Map<string, { account: Account; saved: string }>();
  /** Rooms ended during the current operation, so the caller can close their sockets. */
  ended = new Set<string>();
  constructor(
    public db: Sql,
    public now = Date.now(),
  ) {
    for (const statement of SCHEMA) db.exec(statement);
  }
  begin(now: number) {
    this.now = now;
    this.cache.clear();
    this.ended.clear();
  }
  private rows(query: string, ...params: SqlValue[]) {
    return this.db.exec(query, ...params);
  }
  private row(query: string, ...params: SqlValue[]): Row | undefined {
    return this.db.exec(query, ...params)[0];
  }
  count(table: string) {
    requireThat(/^[a-z]+$/.test(table), "invalid_table", 500);
    return num(this.row(`SELECT COUNT(*) AS n FROM ${table}`)?.n);
  }

  // Accounts
  private toAccount(r: Row): Account {
    const a: Account = {
      id: String(r.id),
      subject: String(r.subject),
      profile: {
        name: String(r.name),
        intro: String(r.intro),
        icon: String(r.icon),
      },
      adult: num(r.adult) === 1,
      consent: num(r.consent) === 1,
      ble: num(r.ble) === 1,
      created: num(r.created),
    };
    if (num(r.disabled) === 1) a.disabled = true;
    if (r.apple != null) a.apple = String(r.apple);
    if (r.apple_checked != null) a.appleChecked = num(r.apple_checked);
    if (r.push != null) a.push = String(r.push);
    if (r.key != null) a.key = JSON.parse(String(r.key));
    return a;
  }
  private remember(a: Account) {
    const hit = this.cache.get(a.id);
    if (hit) return hit.account;
    this.cache.set(a.id, { account: a, saved: JSON.stringify(a) });
    return a;
  }
  private write(a: Account) {
    this.db.exec(
      `INSERT INTO accounts(id, subject, name, intro, icon, adult, consent, ble, created, disabled,
        apple, apple_checked, push, key) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET subject=excluded.subject, name=excluded.name,
        intro=excluded.intro, icon=excluded.icon, adult=excluded.adult, consent=excluded.consent,
        ble=excluded.ble, created=excluded.created, disabled=excluded.disabled,
        apple=excluded.apple, apple_checked=excluded.apple_checked, push=excluded.push, key=excluded.key`,
      a.id,
      a.subject,
      a.profile.name,
      a.profile.intro,
      a.profile.icon,
      a.adult ? 1 : 0,
      a.consent ? 1 : 0,
      a.ble ? 1 : 0,
      a.created,
      a.disabled ? 1 : 0,
      a.apple ?? null,
      a.appleChecked ?? null,
      a.push ?? null,
      a.key ? JSON.stringify(a.key) : null,
    );
  }
  /** Persist account objects mutated during this operation. */
  flush() {
    for (const entry of this.cache.values()) {
      const now = JSON.stringify(entry.account);
      if (now !== entry.saved) {
        this.write(entry.account);
        entry.saved = now;
      }
    }
  }
  /** Any account, including disabled ones. */
  find(id: string): Account | undefined {
    const hit = this.cache.get(id);
    if (hit) return hit.account;
    const r = this.row(`SELECT * FROM accounts WHERE id = ?`, id);
    return r ? this.remember(this.toAccount(r)) : undefined;
  }
  bySubject(subject: string): Account | undefined {
    const r = this.row(`SELECT * FROM accounts WHERE subject = ?`, subject);
    return r ? this.find(String(r.id)) : undefined;
  }
  create(a: Account) {
    this.write(a);
    return this.remember(a);
  }
  account(id: string) {
    const a = this.find(id);
    requireThat(a && !a.disabled, "unauthorized", 401);
    return a;
  }
  ready(id: string) {
    const a = this.account(id);
    requireThat(a.adult && a.consent, "consent_required", 403);
    return a;
  }
  /** Usable as a peer: exists and is not suspended. */
  active(id: string) {
    const a = this.find(id);
    return a && !a.disabled ? a : undefined;
  }

  // Sessions
  private toSession(r: Row): Session {
    return {
      account: String(r.account),
      access: String(r.access),
      refresh: String(r.refresh),
      accessUntil: num(r.access_until),
      refreshUntil: num(r.refresh_until),
    };
  }
  session(access: string): Session | undefined {
    const r = this.row(`SELECT * FROM sessions WHERE access = ?`, access);
    return r ? this.toSession(r) : undefined;
  }
  sessionByRefresh(refresh: string): Session | undefined {
    const r = this.row(
      `SELECT * FROM sessions WHERE refresh = ? AND refresh_until > ?`,
      refresh,
      this.now,
    );
    return r ? this.toSession(r) : undefined;
  }
  addSession(s: Session) {
    this.db.exec(
      `INSERT INTO sessions(access, account, refresh, access_until, refresh_until) VALUES(?,?,?,?,?)`,
      s.access,
      s.account,
      s.refresh,
      s.accessUntil,
      s.refreshUntil,
    );
  }
  dropSession(access: string) {
    this.db.exec(`DELETE FROM sessions WHERE access = ?`, access);
  }
  dropSessionsOf(account: string) {
    this.db.exec(`DELETE FROM sessions WHERE account = ?`, account);
  }

  // Encounter tokens, receipts, challenges, tickets
  addToken(hash: string, account: string, until: number) {
    this.db.exec(
      `INSERT OR REPLACE INTO tokens(hash, account, until) VALUES(?,?,?)`,
      hash,
      account,
      until,
    );
  }
  token(hash: string) {
    const r = this.row(
      `SELECT * FROM tokens WHERE hash = ? AND until > ?`,
      hash,
      this.now,
    );
    return r ? { account: String(r.account), until: num(r.until) } : undefined;
  }
  dropTokensOf(account: string) {
    this.db.exec(`DELETE FROM tokens WHERE account = ?`, account);
  }
  receiptUsed(hash: string) {
    return !!this.row(
      `SELECT 1 AS x FROM receipts WHERE hash = ? AND until > ?`,
      hash,
      this.now,
    );
  }
  addReceipt(hash: string, until: number) {
    this.db.exec(
      `INSERT OR REPLACE INTO receipts(hash, until) VALUES(?,?)`,
      hash,
      until,
    );
  }
  addChallenge(id: string, nonce: string, until: number) {
    this.db.exec(
      `INSERT INTO challenges(id, nonce, until) VALUES(?,?,?)`,
      id,
      nonce,
      until,
    );
  }
  /** Challenges are single use: always consumed, valid or not. */
  takeChallenge(id: string) {
    const r = this.row(`SELECT * FROM challenges WHERE id = ?`, id);
    this.db.exec(`DELETE FROM challenges WHERE id = ?`, id);
    return r && num(r.until) > this.now ? String(r.nonce) : undefined;
  }
  addTicket(hash: string, account: string, room: string, until: number) {
    this.db.exec(
      `INSERT INTO tickets(hash, account, room, until) VALUES(?,?,?,?)`,
      hash,
      account,
      room,
      until,
    );
  }
  takeTicket(hash: string) {
    const r = this.row(`SELECT * FROM tickets WHERE hash = ?`, hash);
    this.db.exec(`DELETE FROM tickets WHERE hash = ?`, hash);
    return r && num(r.until) > this.now
      ? { account: String(r.account), room: String(r.room) }
      : undefined;
  }

  // Moderation
  banned(key: string) {
    return !!this.row(
      `SELECT 1 AS x FROM bans WHERE key = ? AND until > ?`,
      key,
      this.now,
    );
  }
  ban(key: string, until: number) {
    this.db.exec(
      `INSERT OR REPLACE INTO bans(key, until) VALUES(?,?)`,
      key,
      until,
    );
  }
  unban(key: string) {
    this.db.exec(`DELETE FROM bans WHERE key = ?`, key);
  }
  addReport(r: Report) {
    this.db.exec(
      `INSERT INTO reports(reporter, target, reason, until) VALUES(?,?,?,?)`,
      r.by,
      r.target,
      r.reason,
      r.until,
    );
  }
  reports(): Report[] {
    return this.rows(
      `SELECT * FROM reports WHERE until > ? ORDER BY id`,
      this.now,
    ).map((r) => ({
      by: String(r.reporter),
      target: String(r.target),
      reason: String(r.reason),
      until: num(r.until),
    }));
  }
  deletions(limit: number) {
    return this.rows(
      `SELECT * FROM deletions ORDER BY until LIMIT ?`,
      limit,
    ).map((r) => ({
      account: String(r.account),
      apple: String(r.apple),
      until: num(r.until),
    }));
  }
  dropDeletion(account: string) {
    this.db.exec(`DELETE FROM deletions WHERE account = ?`, account);
  }

  blocked(a: string, b: string) {
    return !!this.row(
      `SELECT 1 AS x FROM blocks WHERE (blocker = ? AND blocked = ?) OR (blocker = ? AND blocked = ?)`,
      a,
      b,
      b,
      a,
    );
  }
  allowed(a: string, b: string) {
    this.ready(a);
    this.ready(b);
    requireThat(a !== b && !this.blocked(a, b), "unavailable", 403);
  }
  /**
   * High-frequency limits (per minute / per hour / global) are counted in memory so ordinary reads
   * write no rows. They reset if the object restarts, which only makes them more lenient.
   */
  private counters = new Map<string, { n: number; until: number }>();
  burst(key: string, max: number, ms: number) {
    let r = this.counters.get(key);
    if (!r || r.until <= this.now) {
      r = { n: 0, until: this.now + ms };
      this.counters.set(key, r);
    }
    requireThat(++r.n <= max, "rate_limited", 429);
  }
  /** Durable daily limits (requests, tokens, reports) that must survive restarts. */
  rate(key: string, max: number, ms: number) {
    const r = this.row(`SELECT n, until FROM rates WHERE key = ?`, key);
    const n = r && num(r.until) > this.now ? num(r.n) + 1 : 1;
    const until = r && num(r.until) > this.now ? num(r.until) : this.now + ms;
    this.db.exec(
      `INSERT OR REPLACE INTO rates(key, n, until) VALUES(?,?,?)`,
      key,
      n,
      until,
    );
    requireThat(n <= max, "rate_limited", 429);
  }

  // Encounters and connections
  encounterUntil(a: string, b: string) {
    const r = this.row(
      `SELECT until FROM encounters WHERE pair = ? AND until > ?`,
      pair(a, b),
      this.now,
    );
    return r ? num(r.until) : undefined;
  }
  encounter(a: string, b: string, expires = this.now + DAY) {
    this.allowed(a, b);
    if (this.encounterUntil(a, b) === undefined)
      this.db.exec(
        `INSERT OR REPLACE INTO encounters(pair, a, b, until) VALUES(?,?,?,?)`,
        pair(a, b),
        a,
        b,
        Math.min(this.now + DAY, expires),
      );
  }
  /** Live encounters of an account: peer id and expiry. */
  encountersOf(id: string) {
    return this.rows(
      `SELECT a, b, until FROM encounters WHERE (a = ? OR b = ?) AND until > ?`,
      id,
      id,
      this.now,
    ).map((r) => ({
      peer: String(r.a) === id ? String(r.b) : String(r.a),
      until: num(r.until),
    }));
  }
  connected(a: string, b: string) {
    return !!this.row(
      `SELECT 1 AS x FROM connections WHERE pair = ?`,
      pair(a, b),
    );
  }
  connectionsOf(id: string) {
    return this.rows(
      `SELECT a, b FROM connections WHERE a = ? OR b = ?`,
      id,
      id,
    ).map((r) => (String(r.a) === id ? String(r.b) : String(r.a)));
  }
  disconnect(a: string, b: string) {
    this.db.exec(`DELETE FROM connections WHERE pair = ?`, pair(a, b));
  }

  // Requests
  private toRequest(r: Row): RequestRecord {
    return {
      id: String(r.id),
      from: String(r.sender),
      to: String(r.recipient),
      status: String(r.status) as RequestRecord["status"],
      until: num(r.until),
    };
  }
  private getRequest(id: string) {
    const r = this.row(`SELECT * FROM requests WHERE id = ?`, id);
    return r ? this.toRequest(r) : undefined;
  }
  private setStatus(id: string, status: RequestRecord["status"]) {
    this.db.exec(`UPDATE requests SET status = ? WHERE id = ?`, status, id);
  }
  requestsOf(id: string) {
    return this.rows(
      `SELECT * FROM requests WHERE (sender = ? OR recipient = ?) AND until > ?`,
      id,
      id,
      this.now,
    ).map((r) => this.toRequest(r));
  }
  hasRequestBetween(a: string, b: string) {
    return !!this.row(
      `SELECT 1 AS x FROM requests WHERE pair = ? AND until > ?`,
      pair(a, b),
      this.now,
    );
  }
  /** Returns the open request between the two, creating one if needed. */
  request(a: string, b: string): { request: RequestRecord; created: boolean } {
    this.allowed(a, b);
    const k = pair(a, b);
    const connected = this.connected(a, b);
    const met = this.encounterUntil(a, b);
    requireThat(connected || met !== undefined, "encounter_expired", 403);
    const old = this.row(
      `SELECT * FROM requests WHERE pair = ? AND until > ? AND status IN ('pending', 'accepted')`,
      k,
      this.now,
    );
    if (old) return { request: this.toRequest(old), created: false };
    this.rate(`request:${a}`, 20, DAY);
    const r: RequestRecord = {
      id: uid(),
      from: a,
      to: b,
      status: "pending",
      until: Math.min(this.now + DAY, connected ? Infinity : met!),
    };
    this.db.exec(
      `INSERT INTO requests(id, sender, recipient, pair, status, until) VALUES(?,?,?,?,?,?)`,
      r.id,
      r.from,
      r.to,
      k,
      r.status,
      r.until,
    );
    return { request: r, created: true };
  }
  respond(a: string, id: string, accept: boolean) {
    const r = this.getRequest(id);
    requireThat(r && r.to === a && r.until > this.now, "unavailable", 404);
    this.allowed(a, r.from);
    requireThat(
      r.status === "pending" || (accept && r.status === "accepted"),
      "invalid_state",
      409,
    );
    r.status = accept ? "accepted" : "declined";
    this.setStatus(id, r.status);
    return r;
  }

  // Rooms
  private toRoom(r: Row): Room {
    return {
      id: String(r.id),
      a: String(r.a),
      b: String(r.b),
      ended: num(r.ended) === 1,
      created: num(r.created),
      intents: JSON.parse(String(r.intents)),
      beats: { [String(r.a)]: num(r.beat_a), [String(r.b)]: num(r.beat_b) },
    };
  }
  private fresh(r: Room) {
    return Object.values(r.beats).every((t) => this.now - t < STALE_BEAT);
  }
  /** Live rooms of an account. */
  roomsOf(id: string) {
    return this.rows(
      `SELECT * FROM rooms WHERE (a = ? OR b = ?) AND ended = 0`,
      id,
      id,
    )
      .map((r) => this.toRoom(r))
      .filter((r) => this.fresh(r));
  }
  start(a: string, id: string) {
    const r = this.getRequest(id);
    requireThat(
      r && [r.from, r.to].includes(a) && r.until > this.now,
      "unavailable",
      404,
    );
    this.allowed(r.from, r.to);
    requireThat(r.status === "accepted", "approval_required", 403);
    requireThat(
      !this.row(
        `SELECT 1 AS x FROM rooms WHERE ended = 0 AND (a IN (?, ?) OR b IN (?, ?))`,
        r.from,
        r.to,
        r.from,
        r.to,
      ),
      "already_in_conversation",
      409,
    );
    this.setStatus(id, "used");
    const room: Room = {
      id: uid(),
      a: r.from,
      b: r.to,
      ended: false,
      created: this.now,
      intents: [],
      beats: { [r.from]: this.now, [r.to]: this.now },
    };
    this.db.exec(
      `INSERT INTO rooms(id, a, b, ended, created, intents, beat_a, beat_b) VALUES(?,?,?,0,?,'[]',?,?)`,
      room.id,
      room.a,
      room.b,
      room.created,
      this.now,
      this.now,
    );
    return room;
  }
  room(a: string, id: string) {
    const row = this.row(`SELECT * FROM rooms WHERE id = ?`, id);
    const r = row ? this.toRoom(row) : undefined;
    requireThat(
      r && !r.ended && [r.a, r.b].includes(a),
      "conversation_ended",
      410,
    );
    this.allowed(r.a, r.b);
    requireThat(this.fresh(r), "conversation_ended", 410);
    return r;
  }
  beat(room: Room, account: string) {
    room.beats[account] = this.now;
    this.db.exec(
      `UPDATE rooms SET beat_a = CASE WHEN a = ? THEN ? ELSE beat_a END,
        beat_b = CASE WHEN b = ? THEN ? ELSE beat_b END WHERE id = ?`,
      account,
      this.now,
      account,
      this.now,
      room.id,
    );
  }
  end(id: string) {
    const r = this.row(`SELECT ended FROM rooms WHERE id = ?`, id);
    if (r && num(r.ended) === 0) {
      this.db.exec(
        `UPDATE rooms SET ended = 1, intents = '[]' WHERE id = ?`,
        id,
      );
      this.ended.add(id);
    }
  }
  endRoomsOf(account: string) {
    for (const r of this.rows(
      `SELECT id FROM rooms WHERE (a = ? OR b = ?) AND ended = 0`,
      account,
      account,
    ))
      this.end(String(r.id));
  }
  reconnect(a: string, id: string) {
    const r = this.room(a, id);
    if (!r.intents.includes(a)) r.intents.push(a);
    this.db.exec(
      `UPDATE rooms SET intents = ? WHERE id = ?`,
      JSON.stringify(r.intents),
      id,
    );
    if (r.intents.length === 2)
      this.db.exec(
        `INSERT OR REPLACE INTO connections(pair, a, b) VALUES(?,?,?)`,
        pair(r.a, r.b),
        r.a,
        r.b,
      );
  }
  block(a: string, b: string) {
    this.account(a);
    this.account(b);
    requireThat(a !== b, "invalid_target");
    const k = pair(a, b);
    this.db.exec(
      `INSERT OR REPLACE INTO blocks(blocker, blocked) VALUES(?,?)`,
      a,
      b,
    );
    this.db.exec(`DELETE FROM connections WHERE pair = ?`, k);
    this.db.exec(`DELETE FROM encounters WHERE pair = ?`, k);
    for (const r of this.rows(
      `SELECT id FROM rooms WHERE ended = 0 AND ((a = ? AND b = ?) OR (a = ? AND b = ?))`,
      a,
      b,
      b,
      a,
    ))
      this.end(String(r.id));
    this.db.exec(`UPDATE requests SET status = 'declined' WHERE pair = ?`, k);
  }
  remove(a: string) {
    const account = this.find(a);
    requireThat(account, "unavailable", 404);
    if (account.apple)
      this.db.exec(
        `INSERT OR REPLACE INTO deletions(account, apple, until) VALUES(?,?,?)`,
        a,
        account.apple,
        this.now + 35 * DAY,
      );
    this.endRoomsOf(a);
    this.db.exec(`DELETE FROM sessions WHERE account = ?`, a);
    this.db.exec(`DELETE FROM encounters WHERE a = ? OR b = ?`, a, a);
    this.db.exec(`DELETE FROM connections WHERE a = ? OR b = ?`, a, a);
    this.db.exec(
      `DELETE FROM requests WHERE sender = ? OR recipient = ?`,
      a,
      a,
    );
    this.db.exec(`DELETE FROM blocks WHERE blocker = ? OR blocked = ?`, a, a);
    this.db.exec(`DELETE FROM tokens WHERE account = ?`, a);
    this.db.exec(`DELETE FROM tickets WHERE account = ?`, a);
    this.db.exec(`DELETE FROM accounts WHERE id = ?`, a);
    this.cache.delete(a);
  }
  /** Rooms still marked live; used to decide how soon the next maintenance alarm runs. */
  liveRooms() {
    return num(this.row(`SELECT COUNT(*) AS n FROM rooms WHERE ended = 0`)?.n);
  }
  prune() {
    for (const [k, v] of this.counters)
      if (v.until <= this.now) this.counters.delete(k);
    const stale = this.now - STALE_BEAT;
    for (const r of this.rows(
      `SELECT id FROM rooms WHERE ended = 0 AND (beat_a <= ? OR beat_b <= ?)`,
      stale,
      stale,
    ))
      this.end(String(r.id));
    this.db.exec(`DELETE FROM rooms WHERE ended = 1`);
    for (const table of [
      "encounters",
      "tokens",
      "challenges",
      "tickets",
      "rates",
      "requests",
      "receipts",
      "bans",
      "reports",
    ])
      this.db.exec(`DELETE FROM ${table} WHERE until <= ?`, this.now);
    this.db.exec(`DELETE FROM sessions WHERE refresh_until <= ?`, this.now);
  }

  /** One-time import of the legacy snapshot. Live rooms and tickets are dropped (sockets do not survive). */
  importSnapshot(s: Partial<Snapshot>) {
    for (const a of Object.values(s.accounts ?? {})) this.write(a);
    for (const v of Object.values(s.sessions ?? {})) this.addSession(v);
    for (const [k, e] of Object.entries(s.encounters ?? {}))
      this.db.exec(
        `INSERT OR REPLACE INTO encounters(pair, a, b, until) VALUES(?,?,?,?)`,
        k,
        e.a,
        e.b,
        e.until,
      );
    for (const [k, e] of Object.entries(s.connections ?? {}))
      this.db.exec(
        `INSERT OR REPLACE INTO connections(pair, a, b) VALUES(?,?,?)`,
        k,
        e.a,
        e.b,
      );
    for (const r of Object.values(s.requests ?? {}))
      this.db.exec(
        `INSERT OR REPLACE INTO requests(id, sender, recipient, pair, status, until) VALUES(?,?,?,?,?,?)`,
        r.id,
        r.from,
        r.to,
        pair(r.from, r.to),
        r.status,
        // JSON cannot store Infinity; the legacy snapshot keeps it as null.
        Number.isFinite(r.until) ? r.until : this.now + DAY,
      );
    for (const b of Object.values(s.blocks ?? {}))
      this.db.exec(
        `INSERT OR REPLACE INTO blocks(blocker, blocked) VALUES(?,?)`,
        b.from,
        b.to,
      );
    for (const r of s.reports ?? []) this.addReport(r);
    for (const [k, t] of Object.entries(s.tokens ?? {}))
      this.addToken(k, t.account, t.until);
    for (const [k, until] of Object.entries(s.receipts ?? {}))
      this.db.exec(
        `INSERT OR REPLACE INTO receipts(hash, until) VALUES(?,?)`,
        k,
        until,
      );
    for (const [k, c] of Object.entries(s.challenges ?? {}))
      this.addChallenge(k, c.nonce, c.until);
    for (const [k, d] of Object.entries(s.deletions ?? {}))
      this.db.exec(
        `INSERT OR REPLACE INTO deletions(account, apple, until) VALUES(?,?,?)`,
        k,
        d.apple,
        d.until,
      );
    for (const [k, until] of Object.entries(s.bans ?? {})) this.ban(k, until);
  }
}
