#!/usr/bin/env node
// A stand-in for serdabd's admin API (serdabvpn/docs/api.md), in memory, no deps.
//   npm run mock            → http://127.0.0.1:8801, bearer key "dev-key"
//   MOCK_PORT=9000 MOCK_KEY=x npm run mock
import http from "node:http";

const PORT = Number(process.env.MOCK_PORT ?? 8801);
const KEY = process.env.MOCK_KEY ?? "dev-key";
const NAME_RE = /^[a-z0-9][a-z0-9-]{0,31}$/;
const DAY = 86400;
const now = () => Math.floor(Date.now() / 1000);
const T0 = now();

const DEFAULTS = {
  owner: { canShare: true, filtered: false, logged: false, quotaGb: null, speedMbps: null, days: null },
  family: { canShare: true, filtered: true, logged: true, quotaGb: null, speedMbps: null, days: null },
  kid: { canShare: false, filtered: true, logged: true, quotaGb: null, speedMbps: null, days: null },
  guest: { canShare: false, filtered: true, logged: false, quotaGb: 30, speedMbps: 5, days: 21 },
};

const state = { paused: false, devices: new Map(), domains: new Map(), nextIp: 2 };

function mkDevice(name, role, extra = {}) {
  const d = DEFAULTS[role];
  const createdAt = extra.createdAt ?? T0 - 20 * DAY;
  const dev = {
    name,
    role,
    address: `10.7.0.${state.nextIp++}`,
    enabled: true,
    canShare: d.canShare,
    filtered: d.filtered,
    logged: d.logged,
    speedMbps: d.speedMbps,
    quotaGb: d.quotaGb,
    createdAt,
    createdBy: "admin",
    expiresAt: d.days ? createdAt + d.days * DAY : null,
    firstHandshakeAt: createdAt + 600,
    lastHandshakeAt: T0 - 120,
    daily: [],
    sessions: [],
    ...extra,
  };
  state.devices.set(name, dev);
  return dev;
}

// Deterministic pseudo-random so fixtures look the same on every start.
let seed = 7;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);

function fillTraffic(dev, gbPerDay, sessionsPerDay = 2) {
  const days = Math.min(30, Math.max(0, Math.floor((T0 - dev.createdAt) / DAY)));
  for (let i = days; i >= 0; i--) {
    const t = T0 - i * DAY;
    const iso = new Date(t * 1000).toISOString().slice(0, 10);
    const down = Math.floor(gbPerDay * 1e9 * (0.3 + rnd() * 1.4));
    dev.daily.push({ day: iso, down, up: Math.floor(down * (0.15 + rnd() * 0.2)) });
    for (let s = 0; s < sessionsPerDay; s++) {
      const start = t - Math.floor(rnd() * 20 * 3600);
      const len = Math.floor(600 + rnd() * 7000);
      dev.sessions.push({ start, end: start + len, down: Math.floor(down / sessionsPerDay), up: Math.floor(down / sessionsPerDay / 6) });
    }
  }
  dev.sessions.sort((a, b) => b.start - a.start);
}

function fillDomains(name, list, blockedList = []) {
  const rows = [];
  for (let i = 0; i < 260; i++) {
    const blocked = blockedList.length > 0 && rnd() < 0.08;
    const domain = blocked ? blockedList[Math.floor(rnd() * blockedList.length)] : list[Math.floor(rnd() * list.length)];
    const ts = Math.floor((T0 - Math.floor(rnd() * 14 * DAY)) / 60) * 60;
    rows.push({ ts, domain, blocked, count: 1 + Math.floor(rnd() * 6) });
  }
  rows.sort((a, b) => b.ts - a.ts);
  state.domains.set(name, rows);
}

// ── fixtures ────────────────────────────────────────────────────────────
const phone = mkDevice("phone", "owner", { createdAt: T0 - 28 * DAY, address: "10.7.0.2" });
fillTraffic(phone, 1.2);
const wife = mkDevice("wife-phone", "family", { createdAt: T0 - 25 * DAY, lastHandshakeAt: T0 - 40 * 60 });
fillTraffic(wife, 0.8);
fillDomains("wife-phone", ["whatsapp.net", "g.whatsapp.net", "instagram.com", "noon.com", "amazon.ae", "talabat.com", "apple.com"]);
const son = mkDevice("son-phone", "kid", { createdAt: T0 - 22 * DAY, lastHandshakeAt: T0 - 30 });
fillTraffic(son, 2.1, 3);
son.sessions[0].end = null; // connected right now
fillDomains(
  "son-phone",
  ["youtube.com", "i.ytimg.com", "roblox.com", "discord.com", "tiktokv.com", "google.com", "fortnite.com", "reddit.com"],
  ["pornhub.com", "xvideos.com", "onlyfans.com", "chaturbate.com"],
);
const aunt = mkDevice("aunt-salma", "guest", {
  createdAt: T0 - 9 * DAY,
  createdBy: "wife-phone",
  lastHandshakeAt: T0 - 5 * 3600,
});
aunt.expiresAt = T0 + 12 * DAY;
fillTraffic(aunt, 0.3, 1);
const old = mkDevice("cousin-karim", "guest", { createdAt: T0 - 30 * DAY, createdBy: "phone", lastHandshakeAt: T0 - 9 * DAY });
old.expiresAt = T0 - 9 * DAY;
fillTraffic(old, 0.4, 1);
mkDevice("uncle-hedi", "guest", {
  createdAt: T0 - 3 * 3600,
  createdBy: "wife-phone",
  firstHandshakeAt: null,
  lastHandshakeAt: null,
});

// ── views ───────────────────────────────────────────────────────────────
function status(d) {
  const t = now();
  if (!d.enabled) return "disabled";
  if (d.expiresAt && d.expiresAt <= t) return "expired";
  if (state.paused && d.role !== "owner") return "paused";
  const u = usage(d);
  if (d.quotaGb && u.monthDown + u.monthUp >= d.quotaGb * 1e9) return "over_quota";
  if (!d.firstHandshakeAt) return "pending";
  if (d.lastHandshakeAt && t - d.lastHandshakeAt < 180) return "online";
  return "idle";
}

function usage(d) {
  const todayIso = new Date(now() * 1000).toISOString().slice(0, 10);
  const monthIso = todayIso.slice(0, 7);
  const u = { todayDown: 0, todayUp: 0, monthDown: 0, monthUp: 0 };
  for (const x of d.daily) {
    if (x.day === todayIso) {
      u.todayDown += x.down;
      u.todayUp += x.up;
    }
    if (x.day.startsWith(monthIso)) {
      u.monthDown += x.down;
      u.monthUp += x.up;
    }
  }
  return u;
}

function view(d) {
  const out = { ...d, status: status(d), usage: usage(d) };
  delete out.daily;
  delete out.sessions;
  return out;
}

function invitedBy(name) {
  const out = [];
  for (const d of state.devices.values()) {
    if (d.createdBy === name) out.push(d.name, ...invitedBy(d.name));
  }
  return out;
}

function link(d) {
  const conf = `[Interface]\nPrivateKey = MOCK${Buffer.from(d.name).toString("base64")}=\nAddress = ${d.address}/32\nDNS = 10.7.0.1\nMTU = 1380\n\n[Peer]\nPublicKey = 9XLIDKXfCrnpnGbu2AuLwUXp36vdnSsK4RIGC1hZ0VM=\nEndpoint = 34.163.198.164:51820\nAllowedIPs = 0.0.0.0/0, ::/0\nPersistentKeepalive = 25\n`;
  return `serdab://add?c=${Buffer.from(conf).toString("base64url")}&n=${d.name}`;
}

// ── http ────────────────────────────────────────────────────────────────
const send = (res, code, body) => {
  res.writeHead(code, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
};
const fail = (res, code, error) => send(res, code, { error });

async function body(req) {
  let s = "";
  for await (const c of req) s += c;
  if (!s) return {};
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  const p = url.pathname;
  const m = req.method;
  if (req.headers.authorization !== `Bearer ${KEY}`) return fail(res, 401, "bad admin key");
  console.log(`${m} ${p}${url.search}`);

  if (m === "GET" && p === "/admin/v1/overview") {
    const devs = [...state.devices.values()];
    const sum = (k) => devs.reduce((s, d) => s + usage(d)[k], 0);
    const month = { down: sum("monthDown"), up: sum("monthUp") };
    return send(res, 200, {
      ownerName: "Taha",
      paused: state.paused,
      endpoint: "34.163.198.164:51820",
      costPerGb: 0.12,
      devices: { total: devs.length, online: devs.filter((d) => status(d) === "online").length },
      today: { down: sum("todayDown"), up: sum("todayUp") },
      month: { ...month, estCostUsd: Math.round(((month.down + month.up) / 1e9) * 0.12 * 100) / 100 },
    });
  }
  if (m === "GET" && p === "/admin/v1/devices") {
    const list = [...state.devices.values()].sort((a, b) => b.createdAt - a.createdAt).map(view);
    return send(res, 200, { devices: list });
  }
  if (m === "POST" && p === "/admin/v1/devices") {
    const b = await body(req);
    if (!b || !NAME_RE.test(b.name ?? "")) return fail(res, 400, "a device name is lowercase letters, digits and dashes");
    if (!DEFAULTS[b.role] || b.role === "owner") return fail(res, 400, "role must be family, kid or guest");
    if (state.devices.has(b.name)) return fail(res, 409, `'${b.name}' already exists`);
    const d = mkDevice(b.name, b.role, { createdAt: now(), firstHandshakeAt: null, lastHandshakeAt: null });
    if (d.role === "guest") d.expiresAt = d.createdAt + 21 * DAY;
    return send(res, 201, { device: view(d), link: link(d) });
  }
  if (m === "POST" && p === "/admin/v1/pause") {
    const b = await body(req);
    if (!b || typeof b.paused !== "boolean") return fail(res, 400, "paused must be a boolean");
    state.paused = b.paused;
    return send(res, 200, { paused: state.paused });
  }
  if (m === "GET" && p === "/admin/v1/blocked") {
    const limit = Math.min(500, Number(url.searchParams.get("limit") ?? 100));
    const out = [];
    for (const [device, rows] of state.domains) for (const r of rows) if (r.blocked) out.push({ ts: r.ts, device, domain: r.domain, count: r.count });
    out.sort((a, b) => b.ts - a.ts);
    return send(res, 200, { blocked: out.slice(0, limit) });
  }

  const dm = /^\/admin\/v1\/devices\/([^/]+)(\/domains|\/link)?$/.exec(p);
  if (dm) {
    const name = decodeURIComponent(dm[1]);
    const d = state.devices.get(name);
    if (!d) return fail(res, 404, `no device called '${name}'`);
    const sub = dm[2];
    if (m === "GET" && !sub) {
      return send(res, 200, { device: view(d), daily: d.daily.slice(-30), sessions: d.sessions.slice(0, 50), invited: invitedBy(name) });
    }
    if (m === "GET" && sub === "/link") return send(res, 200, { link: link(d) });
    if (m === "GET" && sub === "/domains") {
      const limit = Math.min(1000, Number(url.searchParams.get("limit") ?? 200));
      const before = Number(url.searchParams.get("before") ?? 0);
      const q = (url.searchParams.get("q") ?? "").toLowerCase();
      const blocked = url.searchParams.get("blocked") === "1";
      let rows = state.domains.get(name) ?? [];
      if (before) rows = rows.filter((r) => r.ts < before);
      if (q) rows = rows.filter((r) => r.domain.includes(q));
      if (blocked) rows = rows.filter((r) => r.blocked);
      return send(res, 200, { logged: d.logged, domains: rows.slice(0, limit) });
    }
    if (m === "PATCH" && !sub) {
      const b = await body(req);
      if (!b) return fail(res, 400, "body must be JSON");
      for (const k of ["enabled", "canShare", "filtered", "logged"]) {
        if (k in b && typeof b[k] !== "boolean") return fail(res, 400, `${k} must be a boolean`);
      }
      for (const k of ["speedMbps", "quotaGb", "expiresAt"]) {
        if (k in b && b[k] !== null && !(Number.isInteger(b[k]) && b[k] > 0)) return fail(res, 400, `${k} must be a positive integer or null`);
      }
      if ("role" in b && !DEFAULTS[b.role]) return fail(res, 400, "unknown role");
      for (const k of ["enabled", "role", "canShare", "filtered", "logged", "speedMbps", "quotaGb", "expiresAt"]) {
        if (k in b) d[k] = b[k];
      }
      return send(res, 200, { device: view(d) });
    }
    if (m === "DELETE" && !sub) {
      const revoked = [name, ...invitedBy(name)];
      for (const n of revoked) {
        state.devices.delete(n);
        state.domains.delete(n);
      }
      return send(res, 200, { revoked });
    }
  }
  return fail(res, 404, "not found");
});

server.listen(PORT, "127.0.0.1", () => console.log(`mock serdabd on http://127.0.0.1:${PORT} (key: ${KEY})`));
