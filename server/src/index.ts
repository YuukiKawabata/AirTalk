import { permittedMessage } from "./content-policy";
import { notify } from "./push";
import { DurableObject } from "cloudflare:workers";
import {
  Model,
  Fault,
  requireThat,
  uid,
  pair,
  DAY,
  HOUR,
  type Snapshot,
  type Account,
  type Sql,
} from "./model";
import {
  type Env,
  random,
  hash,
  appleLogin,
  appleRefresh,
  revoke,
  verifyReceipt,
} from "./auth";
const json = (value: unknown, status = 200) =>
  Response.json(value, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
const fail = (err: unknown) =>
  json(
    { code: err instanceof Fault ? err.code : "service_error" },
    err instanceof Fault ? err.status : 503,
  );
const local = (req: Request, e: Env) =>
  e.MODE === "local" &&
  ["localhost", "127.0.0.1", "[::1]"].includes(new URL(req.url).hostname);
const text = (v: unknown, max: number) => {
  requireThat(
    typeof v === "string" &&
      v.trim().length > 0 &&
      new TextEncoder().encode(v).length <= max,
    "invalid_input",
  );
  return v.trim();
};
type Body = Record<string, any> | null;
/** Handlers that need a JSON body call this; a missing body is invalid input. */
const need = (b: Body) => {
  requireThat(b, "invalid_input");
  return b;
};
const positive = (raw: string | undefined, fallback: number) => {
  const n = Number(raw ?? fallback);
  return Number.isInteger(n) && n > 0 ? n : fallback;
};
export default {
  async fetch(req: Request, e: Env): Promise<Response> {
    if (e.ONLINE_ENABLED !== "true")
      return json({ code: "online_unavailable" }, 503);
    // No path, header or body logging.
    return e.PILOT.get(e.PILOT.idFromName("pilot-v1")).fetch(req);
  },
};
interface Attachment {
  account: string;
  room: string;
  session: string;
  last: number;
  ids: string[];
  window: number;
  count: number;
}
type Later = () => Promise<void>;
/**
 * All state lives in this object's SQLite tables, indexed per account, so cost per request does
 * not grow with the number of accounts. Requests are serialized, but network calls to Apple and
 * APNs happen outside the serialized section so one slow call does not hold up everyone else.
 */
export class PilotHub extends DurableObject<Env> {
  m: Model;
  constructor(ctx: DurableObjectState, e: Env) {
    super(ctx, e);
    const sql: Sql = {
      exec: (query, ...params) =>
        ctx.storage.sql.exec(query, ...params).toArray() as any,
    };
    this.m = new Model(sql);
    ctx.blockConcurrencyWhile(async () => {
      // Import the legacy single-value snapshot once. It is left in place (frozen) so that rolling
      // back to the previous release still finds its data; the marker prevents a second import.
      if (!(await ctx.storage.get<number>("tables-v2"))) {
        const legacy = await ctx.storage.get<Snapshot>("control");
        if (legacy) this.m.importSnapshot(legacy);
        await ctx.storage.put("tables-v2", Date.now());
      }
    });
  }
  /** Optional emergency cap on accounts (unset or 0 = no cap). */
  maxAccounts() {
    return positive(this.env.MAX_ACCOUNTS, Infinity);
  }
  /** Run one serialized operation. Errors are returned to the caller, never thrown inside the lock. */
  async locked<T>(fn: () => T | Promise<T>): Promise<T> {
    const out = await this.ctx.blockConcurrencyWhile(async () => {
      this.m.begin(Date.now());
      let result: { value: T } | { error: unknown };
      try {
        result = { value: await fn() };
      } catch (error) {
        result = { error };
      }
      this.m.flush();
      this.closeEnded();
      await this.schedule();
      return result;
    });
    if ("error" in out) throw out.error;
    return out.value;
  }
  async schedule() {
    const now = Date.now();
    const next =
      now +
      (this.ctx.getWebSockets().length
        ? 15_000
        : this.m.liveRooms()
          ? 60_000
          : HOUR);
    const scheduled = await this.ctx.storage.getAlarm();
    // Busy sockets must not continually postpone expiry and revocation jobs.
    if (scheduled === null || scheduled <= now || scheduled > next)
      await this.ctx.storage.setAlarm(next);
  }
  async fetch(req: Request) {
    try {
      const p = new URL(req.url).pathname,
        method = req.method;
      // Read the body before entering the serialized section so slow uploads never block others.
      const body = method === "GET" ? null : await this.body(req);
      if (p === "/v1/auth/apple" && method === "POST")
        return await this.appleAuth(need(body));
      if (p === "/v1/auth/refresh" && method === "POST")
        return await this.refresh(need(body));
      const later: Later[] = [];
      const response = await this.locked(() => {
        this.m.burst(
          "global-api",
          positive(this.env.GLOBAL_DAILY_LIMIT, 5_000_000),
          DAY,
        );
        return this.route(req, body, later);
      });
      for (const job of later) await job().catch(() => {});
      return response;
    } catch (err) {
      return fail(err);
    }
  }
  async body(req: Request): Promise<Body> {
    const reader = req.body?.getReader();
    if (!reader) return null;
    let size = 0;
    const chunks: Uint8Array[] = [];
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 16_384) {
        await reader.cancel();
        throw new Fault("payload_too_large", 413);
      }
      chunks.push(value);
    }
    if (size === 0) return null;
    const data = new Uint8Array(size);
    let at = 0;
    for (const c of chunks) {
      data.set(c, at);
      at += c.length;
    }
    try {
      const v = JSON.parse(new TextDecoder().decode(data));
      requireThat(
        v && typeof v === "object" && !Array.isArray(v),
        "invalid_input",
      );
      return v;
    } catch {
      throw new Fault("invalid_input");
    }
  }
  async session(req: Request, allowDisabled = false) {
    const bearer = req.headers.get("Authorization");
    requireThat(bearer?.startsWith("Bearer "), "unauthorized", 401);
    const h = await hash(bearer!.slice(7));
    const s = this.m.session(h);
    requireThat(s && s.accessUntil > this.m.now, "unauthorized", 401);
    if (allowDisabled) requireThat(this.m.find(s.account), "unauthorized", 401);
    else this.m.account(s.account);
    return { s, h };
  }
  async issue(a: Account, newLogin = true) {
    if (newLogin) {
      a.ble = false;
      delete a.key;
      delete a.push;
      this.m.dropTokensOf(a.id);
    }
    this.m.dropSessionsOf(a.id);
    this.m.endRoomsOf(a.id);
    const accessToken = random(),
      refreshToken = random();
    const h = await hash(accessToken);
    this.m.addSession({
      account: a.id,
      access: h,
      refresh: await hash(refreshToken),
      accessUntil: this.m.now + 15 * 60_000,
      refreshUntil: this.m.now + 30 * DAY,
    });
    return {
      accessToken,
      refreshToken,
      expiresAt: this.m.now + 15 * 60_000,
      accountID: a.id,
    };
  }
  banKey(subject: string) {
    return hash(`ban:${this.env.TOKEN_ENCRYPTION_KEY ?? "local"}:${subject}`);
  }
  /** Sign in with Apple. Anyone may sign up; older 1.4 clients still send an inviteCode, which is ignored. */
  async appleAuth(b: Record<string, any>) {
    const nonce = await this.locked(() => {
      this.m.burst(
        "global-api",
        positive(this.env.GLOBAL_DAILY_LIMIT, 5_000_000),
        DAY,
      );
      const n = this.m.takeChallenge(text(b.challengeID, 64));
      requireThat(n, "challenge_expired", 401);
      return n;
    });
    const login = await appleLogin(
      text(b.code, 4096),
      text(b.identityToken, 8192),
      nonce,
      this.env,
    );
    const banKey = await this.banKey(login.sub);
    return json(
      await this.locked(async () => {
        requireThat(!this.m.banned(banKey), "account_disabled", 403);
        let a = this.m.bySubject(login.sub);
        if (!a) {
          requireThat(
            this.m.count("accounts") < this.maxAccounts(),
            "pilot_full",
            503,
          );
          a = this.m.create({
            id: uid(),
            subject: login.sub,
            profile: { name: "", intro: "", icon: "person.circle" },
            adult: false,
            consent: false,
            ble: false,
            created: this.m.now,
          });
        }
        requireThat(!a.disabled, "account_disabled", 403);
        a.apple = login.refresh;
        a.appleChecked = this.m.now;
        return await this.issue(a);
      }),
    );
  }
  async refresh(b: Record<string, any>) {
    const h = await hash(text(b.refreshToken, 128));
    const pre = await this.locked(() => {
      this.m.burst(
        "global-api",
        positive(this.env.GLOBAL_DAILY_LIMIT, 5_000_000),
        DAY,
      );
      const s = this.m.sessionByRefresh(h);
      requireThat(s, "unauthorized", 401);
      const a = this.m.account(s.account);
      const recheck =
        a.apple && (a.appleChecked ?? 0) < this.m.now - DAY
          ? a.apple
          : undefined;
      return { access: s.access, apple: recheck };
    });
    if (pre.apple) {
      try {
        await appleRefresh(pre.apple, this.env);
      } catch {
        await this.locked(() => this.m.dropSession(pre.access));
        throw new Fault("unauthorized", 401);
      }
    }
    return json(
      await this.locked(async () => {
        const s = this.m.sessionByRefresh(h);
        requireThat(s && s.access === pre.access, "unauthorized", 401);
        const a = this.m.account(s.account);
        if (pre.apple) a.appleChecked = this.m.now;
        // Rotation ends any active conversation and invalidates old sockets.
        return await this.issue(a, false);
      }),
    );
  }
  async route(req: Request, body: Body, later: Later[]): Promise<Response> {
    const url = new URL(req.url),
      p = url.pathname,
      method = req.method;
    if (p === "/health" && method === "GET")
      return json({ status: "ok", mode: this.env.MODE });
    if (p.startsWith("/admin/")) {
      const bearer = req.headers.get("Authorization")?.replace(/^Bearer /, "");
      requireThat(
        this.env.ADMIN_TOKEN &&
          this.env.ADMIN_TOKEN.length >= 32 &&
          bearer &&
          (await hash(bearer)) === (await hash(this.env.ADMIN_TOKEN)),
        "unauthorized",
        401,
      );
      if (p === "/admin/reports" && method === "GET")
        return json({
          reports: this.m.reports(),
          revocationsPending: this.m.count("deletions"),
          accounts: this.m.count("accounts"),
        });
      if (p === "/admin/suspend" && method === "POST") {
        const account = this.m.account(text(need(body).accountID, 64));
        account.disabled = true;
        this.m.ban(await this.banKey(account.subject), this.m.now + 180 * DAY);
        this.m.endRoomsOf(account.id);
        return json({ ok: true });
      }
      if (p === "/admin/restore" && method === "POST") {
        const account = this.m.find(text(need(body).accountID, 64));
        requireThat(account, "account_not_found", 404);
        this.m.unban(await this.banKey(account.subject));
        account.disabled = false;
        return json({ ok: true });
      }
      if (p === "/admin/delete" && method === "POST") {
        this.m.remove(text(need(body).accountID, 64));
        return json({ ok: true });
      }
      throw new Fault("not_found", 404);
    }
    if (p === "/v1/auth/apple/challenge" && method === "POST") {
      // Generous per-IP limit: many people share one IP behind carrier NAT or venue Wi-Fi.
      const ip = await hash(req.headers.get("CF-Connecting-IP") ?? "local");
      this.m.burst(`auth:${ip}`, 300, HOUR);
      const id = uid(),
        nonce = random();
      this.m.addChallenge(id, nonce, this.m.now + 300_000);
      return json({ id, nonce });
    }
    if (p === "/v1/dev/login" && method === "POST") {
      requireThat(local(req, this.env), "not_found", 404);
      const b = need(body);
      const subject = `local:${text(b.name, 48)}`;
      let a = this.m.bySubject(subject);
      if (!a) {
        requireThat(
          this.m.count("accounts") < this.maxAccounts(),
          "pilot_full",
          503,
        );
        a = this.m.create({
          id: uid(),
          subject,
          profile: { name: b.name, intro: "", icon: "person.circle" },
          adult: true,
          consent: true,
          ble: false,
          created: this.m.now,
        });
      }
      return json(await this.issue(a));
    }
    if (p.match(/^\/v1\/conversations\/[^/]+\/socket$/) && method === "GET")
      return this.upgrade(req, p.split("/")[3]);
    const exiting =
      (p === "/v1/me" && method === "DELETE") || p === "/v1/auth/logout";
    const { h, s } = await this.session(req, exiting),
      a = exiting ? this.m.find(s.account)! : this.m.account(s.account);
    this.m.burst(`api:${a.id}`, 300, 60_000);
    if (p === "/v1/auth/logout" && method === "POST") {
      this.m.dropSession(h);
      delete a.push;
      this.m.endRoomsOf(a.id);
      return json({ ok: true });
    }
    if (p === "/v1/me" && method === "DELETE") {
      this.m.remove(a.id);
      return json({ ok: true });
    }
    const me = () => ({
      id: a.id,
      ...a.profile,
      adult: a.adult,
      consent: a.consent,
      ble: a.ble,
    });
    if (p === "/v1/me/profile" && method === "GET") return json(me());
    if (p === "/v1/me/profile" && method === "PATCH") {
      const b = need(body);
      a.profile = {
        name: text(b.name, 48),
        intro:
          typeof b.intro === "string" &&
          new TextEncoder().encode(b.intro).length <= 120
            ? b.intro
            : "",
        icon: [
          "person.circle",
          "leaf.fill",
          "headphones",
          "book.fill",
        ].includes(b.icon)
          ? b.icon
          : "person.circle",
      };
      return json(me());
    }
    if (p === "/v1/me/consents" && method === "PUT") {
      const b = need(body);
      requireThat(
        b.version === "pilot-1" && b.adult === true && b.consent === true,
        "consent_required",
        403,
      );
      a.adult = true;
      a.consent = true;
      a.ble = b.ble === true;
      if (!a.ble) this.m.dropTokensOf(a.id);
      return json({ ok: true });
    }
    this.m.ready(a.id);
    if (p === "/v1/me/push" && method === "PUT") {
      const b = need(body);
      requireThat(
        typeof b.token === "string" && /^[a-f0-9]{64}$/.test(b.token),
        "invalid_token",
      );
      a.push = b.token;
      return json({ ok: true });
    }
    if (p === "/v1/me/push" && method === "DELETE") {
      delete a.push;
      return json({ ok: true });
    }
    if (p === "/v1/me/device" && method === "PUT") {
      const b = need(body);
      requireThat(
        b.key?.kty === "EC" && b.key?.crv === "P-256" && !b.key.d,
        "invalid_key",
      );
      await crypto.subtle.importKey(
        "jwk",
        b.key,
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["verify"],
      );
      a.key = { kty: "EC", crv: "P-256", x: b.key.x, y: b.key.y };
      this.m.dropTokensOf(a.id);
      return json({ ok: true });
    }
    if (p === "/v1/encounter-tokens" && method === "POST") {
      requireThat(a.ble && a.key, "ble_consent_required", 403);
      this.m.rate(`tokens:${a.id}`, 100, DAY);
      const token = random(),
        until = this.m.now + DAY;
      this.m.addToken(await hash(token), a.id, until);
      return json({ token, expiresAt: until });
    }
    if (p === "/v1/encounter-receipts" && method === "POST") {
      const b = need(body);
      const fields = ["tokenA", "tokenB", "challengeA", "challengeB"] as const;
      for (const f of fields)
        requireThat(
          typeof b[f] === "string" && /^[A-Za-z0-9_-]{43}$/.test(b[f]),
          "invalid_receipt",
        );
      const ta = this.m.token(await hash(b.tokenA)),
        tb = this.m.token(await hash(b.tokenB));
      requireThat(
        ta && tb && [ta.account, tb.account].includes(a.id),
        "receipt_expired",
        403,
      );
      const aa = this.m.ready(ta.account),
        bb = this.m.ready(tb.account);
      requireThat(
        aa.ble && bb.ble && aa.key && bb.key,
        "ble_consent_required",
        403,
      );
      const payload = ["airtalk-encounter-v1", ...fields.map((f) => b[f])].join(
        "\n",
      );
      requireThat(
        (await verifyReceipt(aa.key, payload, text(b.signatureA, 128))) &&
          (await verifyReceipt(bb.key, payload, text(b.signatureB, 128))),
        "invalid_signature",
        403,
      );
      const rh = await hash(payload);
      if (!this.m.receiptUsed(rh)) {
        this.m.encounter(aa.id, bb.id, Math.min(ta.until, tb.until));
        this.m.addReceipt(rh, this.m.now + DAY);
      }
      return json({ ok: true });
    }
    if (p === "/v1/dev/encounter" && method === "POST") {
      requireThat(local(req, this.env), "not_found", 404);
      this.m.encounter(a.id, text(need(body).peerID, 64));
      return json({ ok: true });
    }
    const card = (id: string) => {
      const peer = this.m.active(id);
      return peer && { id, ...peer.profile };
    };
    if (p === "/v1/encounters" && method === "GET")
      return json({
        people: this.m
          .encountersOf(a.id)
          .filter((e) => !this.m.blocked(a.id, e.peer))
          .flatMap((e) => {
            const c = card(e.peer);
            return c ? [{ ...c, expiresAt: e.until }] : [];
          }),
      });
    if (p === "/v1/connections" && method === "GET")
      return json({
        people: this.m.connectionsOf(a.id).flatMap((peer) => {
          const c = card(peer);
          return c ? [c] : [];
        }),
      });
    if (p.startsWith("/v1/connections/") && method === "DELETE") {
      this.m.disconnect(a.id, p.split("/")[3]);
      return json({ ok: true });
    }
    if (p === "/v1/requests" && method === "GET")
      return json({
        requests: this.m
          .requestsOf(a.id)
          .filter((r) => !this.m.blocked(r.from, r.to))
          .flatMap((r) => {
            const c = card(r.from === a.id ? r.to : r.from);
            return c ? [{ ...r, peer: c }] : [];
          }),
      });
    if (p === "/v1/requests" && method === "POST") {
      const { request, created } = this.m.request(
        a.id,
        text(need(body).peerID, 64),
      );
      const target = this.m.find(request.to);
      const token = target?.push;
      if (token && created)
        later.push(async () => {
          // APNs is contacted outside the serialized section.
          if ((await notify(token, this.env)) === "invalid")
            await this.locked(() => {
              const t = this.m.find(request.to);
              if (t?.push === token) delete t.push;
            });
        });
      return json(request);
    }
    if (
      /^\/v1\/requests\/[^/]+\/(accept|decline)$/.test(p) &&
      method === "POST"
    )
      return json(this.m.respond(a.id, p.split("/")[3], p.endsWith("/accept")));
    if (p === "/v1/conversations" && method === "GET")
      return json({
        rooms: this.m.roomsOf(a.id).flatMap((r) => {
          const c = card(r.a === a.id ? r.b : r.a);
          return c ? [{ id: r.id, peer: c }] : [];
        }),
      });
    if (p === "/v1/conversations" && method === "POST")
      return json(this.m.start(a.id, text(need(body).requestID, 64)));
    if (
      /^\/v1\/conversations\/[^/]+\/(ticket|end|reconnect-intent)$/.test(p) &&
      method === "POST"
    ) {
      const id = p.split("/")[3];
      const r = this.m.room(a.id, id);
      if (p.endsWith("/end")) {
        this.m.end(id);
        return json({ ok: true });
      }
      if (p.endsWith("/reconnect-intent")) {
        this.m.reconnect(a.id, id);
        return json({ ok: true });
      }
      const ticket = random();
      this.m.addTicket(await hash(ticket), a.id, r.id, this.m.now + 30_000);
      return json({ ticket });
    }
    if ((p === "/v1/blocks" || p === "/v1/reports") && method === "POST") {
      const b = need(body),
        target = text(b.peerID, 64);
      this.m.rate(`safety:${a.id}`, 30, DAY);
      // Only people this account has actually encountered or interacted with can be reported.
      requireThat(
        this.m.encounterUntil(a.id, target) !== undefined ||
          this.m.connected(a.id, target) ||
          this.m.hasRequestBetween(a.id, target),
        "unavailable",
        404,
      );
      if (p === "/v1/reports") {
        requireThat(
          ["harassment", "sexual", "spam", "underage", "other"].includes(
            b.reason,
          ),
          "invalid_reason",
        );
        this.m.addReport({
          by: a.id,
          target,
          reason: b.reason,
          until: this.m.now + 90 * DAY,
        });
      }
      this.m.block(a.id, target);
      return json({ ok: true });
    }
    throw new Fault("not_found", 404);
  }
  async upgrade(req: Request, roomID: string) {
    const { s, h } = await this.session(req);
    const t = req.headers.get("X-AirTalk-Ticket");
    requireThat(t, "unauthorized", 401);
    const ticket = this.m.takeTicket(await hash(t));
    requireThat(
      ticket && ticket.account === s.account && ticket.room === roomID,
      "unauthorized",
      401,
    );
    this.m.room(s.account, roomID);
    requireThat(
      req.headers.get("Upgrade")?.toLowerCase() === "websocket",
      "upgrade_required",
      426,
    );
    requireThat(
      this.ctx.getWebSockets(`acct:${s.account}`).length === 0,
      "already_connected",
      409,
    );
    const ws = new WebSocketPair();
    this.ctx.acceptWebSocket(ws[1], [`room:${roomID}`, `acct:${s.account}`]);
    ws[1].serializeAttachment({
      account: s.account,
      room: roomID,
      session: h,
      last: this.m.now,
      ids: [],
      window: this.m.now,
      count: 0,
    } satisfies Attachment);
    const other = this.peer(roomID, s.account);
    if (other) {
      this.valid(other);
      other.send(JSON.stringify({ type: "ready" }));
      ws[1].send(JSON.stringify({ type: "ready" }));
    }
    return new Response(null, { status: 101, webSocket: ws[0] });
  }
  peer(room: string, account: string) {
    return this.ctx
      .getWebSockets(`room:${room}`)
      .find(
        (socket) =>
          (socket.deserializeAttachment() as Attachment).account !== account,
      );
  }
  valid(ws: WebSocket) {
    requireThat(this.env.ONLINE_ENABLED === "true", "online_unavailable", 503);
    const a = ws.deserializeAttachment() as Attachment;
    const s = this.m.session(a.session);
    requireThat(s && s.accessUntil > this.m.now, "unauthorized", 401);
    const r = this.m.room(a.account, a.room);
    return { a, r };
  }
  close(ws: WebSocket) {
    try {
      ws.close(1000, "ended");
    } catch {}
  }
  /** Close sockets of rooms ended during the current operation. */
  closeEnded() {
    for (const room of this.m.ended)
      for (const ws of this.ctx.getWebSockets(`room:${room}`)) this.close(ws);
    this.m.ended.clear();
  }
  /** Re-validate every open socket (session expiry, suspension); run from the alarm. */
  sweep() {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        this.valid(ws);
      } catch {
        this.close(ws);
      }
    }
  }
  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    await this.locked(() => {
      try {
        const { a, r } = this.valid(ws);
        requireThat(
          typeof message === "string" &&
            new TextEncoder().encode(message).length <= 8192,
          "invalid_frame",
        );
        const f = JSON.parse(message);
        requireThat(f.v === 1 && f.conversationID === r.id, "invalid_frame");
        if (this.m.now - a.window >= 60_000) {
          a.window = this.m.now;
          a.count = 0;
        }
        requireThat(++a.count <= 120, "rate_limited", 429);
        a.last = this.m.now;
        this.m.beat(r, a.account);
        if (f.type === "heartbeat")
          ws.send(JSON.stringify({ type: "heartbeat" }));
        else if (f.type === "end") this.m.end(r.id);
        else {
          requireThat(
            f.type === "message" &&
              typeof f.id === "string" &&
              /^[a-fA-F0-9-]{36}$/.test(f.id),
            "invalid_frame",
          );
          const body = text(f.text, 4000);
          requireThat([...body].length <= 1000, "invalid_frame");
          if (!permittedMessage(body)) {
            ws.send(
              JSON.stringify({
                type: "rejected",
                id: f.id,
                code: "message_not_allowed",
              }),
            );
          } else if (!a.ids.includes(f.id)) {
            a.ids.push(f.id);
            if (a.ids.length > 200) a.ids.shift();
            const peer = this.peer(r.id, a.account);
            requireThat(peer, "peer_not_connected", 409);
            this.valid(peer);
            // Never write body into storage, attachments, logs or retry queues.
            peer.send(
              JSON.stringify({
                type: "message",
                id: f.id,
                text: body,
                sender: a.account,
              }),
            );
            ws.send(JSON.stringify({ type: "relayed", id: f.id }));
          }
        }
        ws.serializeAttachment(a);
      } catch {
        const a = ws.deserializeAttachment() as Attachment;
        this.m.end(a.room);
        // Also close this socket if its room was already gone.
        this.close(ws);
      }
    });
  }
  async webSocketClose(ws: WebSocket) {
    await this.locked(() => {
      const a = ws.deserializeAttachment() as Attachment;
      this.m.end(a.room);
    });
  }
  async webSocketError(ws: WebSocket) {
    await this.webSocketClose(ws);
  }
  async alarm() {
    // Persist deletion/revocation jobs before contacting Apple; retry without restoring the account.
    const jobs = await this.locked(() => {
      this.m.prune();
      this.sweep();
      return this.m.deletions(5);
    });
    for (const job of jobs) {
      if (job.until <= Date.now()) {
        await this.locked(() => this.m.dropDeletion(job.account));
        continue;
      }
      try {
        await revoke(job.apple, this.env);
        await this.locked(() => this.m.dropDeletion(job.account));
      } catch {
        /* Retain encrypted credential for operator-assisted revocation; never log it. */
      }
    }
  }
}
