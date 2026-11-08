#!/usr/bin/env python3
"""serdabd - the brain of a serdabVPN server.

Owns the devices (WireGuard peers) and their rules: role, expiry, quota, speed,
DNS filter, site log. SQLite is the source of truth; wg0.conf, nftables and tc
are rendered from it. Contract: docs/api.md. Stdlib only (Debian 12, Python 3.11).

  serdabd.py serve          the daemon (systemd: serdabd.service)
  serdabd.py <cli command>  see `serdab help` (the CLI talks to the daemon on 127.0.0.1)

SERDAB_FAKE=1 runs without wg/nft/tc (local development and tests).
"""
from __future__ import annotations

import base64
import hmac
import ipaddress
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from zoneinfo import ZoneInfo

# ── configuration ────────────────────────────────────────────────────────────
ENV = os.environ.get
FAKE = ENV("SERDAB_FAKE") == "1"
ROOT = ENV("SERDAB_ROOT", "")                      # prefix for every path (tests)
DB_PATH = ROOT + ENV("SERDAB_DB", "/var/lib/serdab/serdab.db")
WG_DIR = ROOT + "/etc/wireguard"
WG_IF = "wg0"
ETC = ROOT + "/etc/serdab"
LOG_DIR = ROOT + "/var/log/serdab"
NET = "10.7.0"
SERVER_IP = f"{NET}.1"
DEVICE_PORT = int(ENV("SERDAB_DEVICE_PORT", "8800"))
ADMIN_PORT = int(ENV("SERDAB_ADMIN_PORT", "8801"))
ADMIN_HOSTS = [h for h in ENV("SERDAB_ADMIN_HOSTS", "127.0.0.1").split(",") if h]
OWNER_NAME = ENV("SERDAB_OWNER_NAME", "Taha")
COST_PER_GB = float(ENV("SERDAB_COST_PER_GB", "0.12"))
TZ = ZoneInfo(ENV("SERDAB_TZ", "Asia/Qatar"))
MTU = ENV("SERDAB_MTU", "1380")
TICK = float(ENV("SERDAB_TICK", "30"))
ONLINE_WINDOW = 180          # a handshake younger than this = online
GUEST_DAYS = 21
PENDING_HOURS = 48
LOG_DAYS = 30
AUTO_CLOSE_MIN = int(ENV("SERDAB_AUTO_CLOSE_MIN", "120"))
MAX_GUESTS_PER_SHARER = 10

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
ROLES = ("owner", "family", "kid", "guest")
DEFAULTS = {  # canShare, filtered, logged, quotaGb, speedMbps
    "owner":  (1, 0, 0, None, None),
    "family": (1, 1, 1, None, None),
    "kid":    (0, 1, 1, None, None),
    "guest":  (0, 1, 0, 30, 5),
}
# DNS-over-HTTPS/TLS resolvers a filtered device must not reach directly.
DOH_NETS = ["1.1.1.1", "1.0.0.1", "1.1.1.2", "1.0.0.2", "1.1.1.3", "1.0.0.3",
            "8.8.8.8", "8.8.4.4", "9.9.9.9", "149.112.112.112", "94.140.14.14",
            "94.140.15.15", "208.67.222.222", "208.67.220.220", "45.90.28.0/24",
            "45.90.30.0/24", "185.228.168.0/24", "185.228.169.0/24", "76.76.2.0/24",
            "76.76.10.0/24", "194.242.2.0/24"]
# The tunnel never reaches these: the VM's own network, the metadata server, other peers.
PRIVATE_NETS = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16",
                "100.64.0.0/10", "127.0.0.0/8"]

LOCK = threading.RLock()


def now() -> int:
    return int(time.time())


def day_of(ts: int) -> str:
    return datetime.fromtimestamp(ts, TZ).strftime("%Y-%m-%d")


def month_start(ts: int) -> str:
    return datetime.fromtimestamp(ts, TZ).strftime("%Y-%m-01")


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


# ── database ─────────────────────────────────────────────────────────────────
SCHEMA = """
CREATE TABLE IF NOT EXISTS device (
  name TEXT PRIMARY KEY, role TEXT NOT NULL, ip TEXT NOT NULL UNIQUE,
  priv TEXT NOT NULL, pub TEXT NOT NULL UNIQUE, psk TEXT NOT NULL,
  enabled INT NOT NULL DEFAULT 1, can_share INT NOT NULL, filtered INT NOT NULL,
  logged INT NOT NULL, quota_gb REAL, speed_mbps REAL,
  created_at INT NOT NULL, created_by TEXT NOT NULL, expires_at INT,
  first_hs INT, last_hs INT, gone TEXT            -- gone: 'expired' once removed for good
);
CREATE TABLE IF NOT EXISTS usage (
  name TEXT NOT NULL, day TEXT NOT NULL, down INT NOT NULL DEFAULT 0, up INT NOT NULL DEFAULT 0,
  PRIMARY KEY (name, day)
);
CREATE TABLE IF NOT EXISTS session (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, start INT NOT NULL, end INT,
  down INT NOT NULL DEFAULT 0, up INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS session_name ON session(name, start);
CREATE TABLE IF NOT EXISTS dns (
  name TEXT NOT NULL, minute INT NOT NULL, domain TEXT NOT NULL,
  count INT NOT NULL, blocked INT NOT NULL,
  PRIMARY KEY (name, minute, domain)
);
CREATE INDEX IF NOT EXISTS dns_minute ON dns(minute);
CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT NOT NULL);
"""


class DB:
    def __init__(self, path: str):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.c = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.c.row_factory = sqlite3.Row
        self.c.execute("PRAGMA journal_mode=WAL")
        self.c.executescript(SCHEMA)

    def q(self, sql, *args):
        with LOCK:
            return self.c.execute(sql, args).fetchall()

    def one(self, sql, *args):
        r = self.q(sql, *args)
        return r[0] if r else None

    def x(self, sql, *args):
        with LOCK:
            return self.c.execute(sql, args)

    def get(self, k, default=None):
        r = self.one("SELECT v FROM kv WHERE k=?", k)
        return json.loads(r["v"]) if r else default

    def put(self, k, v):
        self.x("INSERT INTO kv(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", k, json.dumps(v))


# ── system commands ──────────────────────────────────────────────────────────
class Sys:
    """Everything that touches the kernel. FAKE mode keeps a simulated peer table."""

    def __init__(self):
        self.fake_peers: dict[str, dict] = {}   # pub -> {hs, rx, tx}

    def run(self, cmd: str, stdin: str | None = None, check=True) -> str:
        if FAKE:
            return ""
        p = subprocess.run(["bash", "-c", cmd], input=stdin, capture_output=True, text=True)
        if check and p.returncode != 0:
            raise RuntimeError(f"{cmd.split()[0]}: {p.stderr.strip() or p.stdout.strip()}")
        return p.stdout

    def genkey(self) -> tuple[str, str]:
        if FAKE:
            k = base64.b64encode(secrets.token_bytes(32)).decode()
            return k, base64.b64encode(secrets.token_bytes(32)).decode()
        priv = self.run("wg genkey").strip()
        return priv, self.run("wg pubkey", stdin=priv + "\n").strip()

    def genpsk(self) -> str:
        if FAKE:
            return base64.b64encode(secrets.token_bytes(32)).decode()
        return self.run("wg genpsk").strip()

    def dump(self) -> dict[str, dict]:
        """pub -> {hs, rx (from the phone), tx (to the phone)}"""
        if FAKE:
            return {k: dict(v) for k, v in self.fake_peers.items()}
        out = self.run(f"wg show {WG_IF} dump", check=False)
        peers = {}
        for line in out.splitlines()[1:]:
            f = line.split("\t")
            if len(f) >= 7:
                peers[f[0]] = {"hs": int(f[4]), "rx": int(f[5]), "tx": int(f[6])}
        return peers

    def sync_wg(self, conf: str, active_pubs: set[str]):
        path = f"{WG_DIR}/{WG_IF}.conf"
        tmp = path + ".tmp"
        os.makedirs(WG_DIR, exist_ok=True)
        with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
            f.write(conf)
        os.replace(tmp, path)
        if FAKE:
            for pub in list(self.fake_peers):
                if pub not in active_pubs:
                    del self.fake_peers[pub]
            for pub in active_pubs:
                self.fake_peers.setdefault(pub, {"hs": 0, "rx": 0, "tx": 0})
            return
        self.run(f"wg syncconf {WG_IF} <(wg-quick strip {WG_IF})")

    def nft(self, ruleset: str):
        os.makedirs(ETC, exist_ok=True)
        with open(f"{ETC}/rules.nft", "w") as f:
            f.write(ruleset)
        if not FAKE:
            self.run(f"nft -f {ETC}/rules.nft")

    def tc(self, script: str):
        with open(f"{ETC}/tc.sh", "w") as f:
            f.write(script)
        if not FAKE:
            self.run(f"bash {ETC}/tc.sh")


# ── the server ───────────────────────────────────────────────────────────────
class Serdab:
    def __init__(self, db: DB, sysx: Sys):
        self.db, self.sys = db, sysx
        self.applied_sig = None
        self.dns_buf: dict[tuple[str, int, str], list[int]] = {}   # (name, minute, domain) -> [count, blocked]
        self.qid: dict[tuple[str, str], tuple[str, str]] = {}      # (instance, serial) -> (ip, domain)

    # files written by install.sh
    def server_pub(self) -> str:
        return open(f"{WG_DIR}/server.pub").read().strip() if not FAKE or os.path.exists(f"{WG_DIR}/server.pub") else "FAKE-SERVER-PUB="

    def endpoint(self) -> str:
        p = f"{WG_DIR}/endpoint"
        return open(p).read().strip() if os.path.exists(p) else "203.0.113.1:51820"

    # ── import the devices the old bash CLI enrolled ──
    def adopt_legacy(self):
        cdir = f"{WG_DIR}/clients"
        if not os.path.isdir(cdir):
            return
        wgconf = open(f"{WG_DIR}/{WG_IF}.conf").read() if os.path.exists(f"{WG_DIR}/{WG_IF}.conf") else ""
        for fn in sorted(os.listdir(cdir)):
            if not fn.endswith(".conf"):
                continue
            name = fn[:-5]
            if self.db.one("SELECT 1 FROM device WHERE name=?", name):
                continue
            txt = open(f"{cdir}/{fn}").read()
            kv = dict(re.findall(r"^(\w+)\s*=\s*(.+)$", txt, re.M))
            priv, psk, ip = kv["PrivateKey"].strip(), kv["PresharedKey"].strip(), kv["Address"].split("/")[0].strip()
            pub = self.sys.run("wg pubkey", stdin=priv + "\n").strip() if not FAKE else base64.b64encode(secrets.token_bytes(32)).decode()
            role = "owner"   # the only devices the bash CLI ever made were the owner's own
            cs, fl, lg, qg, sp = DEFAULTS[role]
            self.db.x("INSERT INTO device(name,role,ip,priv,pub,psk,can_share,filtered,logged,quota_gb,speed_mbps,created_at,created_by)"
                      " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)", name, role, ip, priv, pub, psk, cs, fl, lg, qg, sp,
                      int(os.path.getmtime(f"{cdir}/{fn}")), "admin")
            log(f"adopted legacy device {name} ({ip}) as {role}")
        if "# serdab:" in wgconf:
            self.db.put("iface", wgconf.split("\n# serdab:")[0].rstrip() + "\n")

    def iface_block(self) -> str:
        blk = self.db.get("iface")
        if blk:
            return blk
        path = f"{WG_DIR}/{WG_IF}.conf"
        txt = open(path).read() if os.path.exists(path) else f"[Interface]\nAddress = {SERVER_IP}/24\n"
        blk = re.split(r"\n(?:# serdab:|\[Peer\])", txt)[0].rstrip() + "\n"
        self.db.put("iface", blk)
        return blk

    # ── device status ──
    def paused(self) -> bool:
        return bool(self.db.get("paused", False))

    def month_bytes(self, name: str) -> tuple[int, int]:
        r = self.db.one("SELECT COALESCE(SUM(down),0) d, COALESCE(SUM(up),0) u FROM usage WHERE name=? AND day>=?",
                        name, month_start(now()))
        return r["d"], r["u"]

    def status(self, d: sqlite3.Row, t: int | None = None) -> str:
        t = t or now()
        if d["gone"] == "expired" or (d["expires_at"] and d["expires_at"] <= t):
            return "expired"
        if not d["enabled"]:
            return "disabled"
        if self.paused() and d["role"] != "owner":
            return "paused"
        if d["quota_gb"] is not None and sum(self.month_bytes(d["name"])) >= d["quota_gb"] * 1e9:
            return "over_quota"
        if not d["first_hs"]:
            return "pending"
        if d["last_hs"] and t - d["last_hs"] < ONLINE_WINDOW:
            return "online"
        return "idle"

    def active(self, d, t=None) -> bool:
        return self.status(d, t) in ("pending", "online", "idle")

    def device_json(self, d) -> dict:
        t = now()
        td = self.db.one("SELECT down, up FROM usage WHERE name=? AND day=?", d["name"], day_of(t))
        md, mu = self.month_bytes(d["name"])
        return {
            "name": d["name"], "role": d["role"], "address": d["ip"], "status": self.status(d, t),
            "enabled": bool(d["enabled"]), "canShare": bool(d["can_share"]), "filtered": bool(d["filtered"]),
            "logged": bool(d["logged"]), "speedMbps": d["speed_mbps"], "quotaGb": d["quota_gb"],
            "createdAt": d["created_at"], "createdBy": d["created_by"], "expiresAt": d["expires_at"],
            "firstHandshakeAt": d["first_hs"], "lastHandshakeAt": d["last_hs"],
            "usage": {"todayDown": td["down"] if td else 0, "todayUp": td["up"] if td else 0,
                      "monthDown": md, "monthUp": mu},
        }

    def devices(self):
        return self.db.q("SELECT * FROM device ORDER BY created_at DESC")

    def device(self, name):
        return self.db.one("SELECT * FROM device WHERE name=?", name)

    # ── create / change / revoke ──
    def next_ip(self) -> str:
        used = {r["ip"] for r in self.db.q("SELECT ip FROM device")}
        for i in range(2, 255):
            if f"{NET}.{i}" not in used:
                return f"{NET}.{i}"
        raise ApiError(409, "no free addresses left")

    def create(self, name: str, role: str, created_by: str) -> sqlite3.Row:
        if not isinstance(name, str) or not NAME_RE.match(name):
            raise ApiError(400, "a name is lowercase letters, digits and dashes (max 32)")
        if role not in ROLES:
            raise ApiError(400, f"role is one of {', '.join(ROLES)}")
        with LOCK:
            if self.device(name):
                raise ApiError(409, f"'{name}' already exists")
            priv, pub = self.sys.genkey()
            cs, fl, lg, qg, sp = DEFAULTS[role]
            t = now()
            exp = t + GUEST_DAYS * 86400 if role == "guest" else None
            self.db.x("INSERT INTO device(name,role,ip,priv,pub,psk,can_share,filtered,logged,quota_gb,speed_mbps,"
                      "created_at,created_by,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                      name, role, self.next_ip(), priv, pub, self.sys.genpsk(), cs, fl, lg, qg, sp, t, created_by, exp)
            log(f"created {name} ({role}) by {created_by}")
            self.apply()
            return self.device(name)

    PATCHABLE = {"enabled": "enabled", "role": "role", "canShare": "can_share", "filtered": "filtered",
                 "logged": "logged", "speedMbps": "speed_mbps", "quotaGb": "quota_gb", "expiresAt": "expires_at"}

    def patch(self, name: str, body: dict) -> sqlite3.Row:
        with LOCK:
            d = self.device(name)
            if not d:
                raise ApiError(404, f"no device called '{name}'")
            sets = {}
            for k, v in body.items():
                col = self.PATCHABLE.get(k)
                if not col:
                    raise ApiError(400, f"unknown field '{k}'")
                if col in ("enabled", "can_share", "filtered", "logged"):
                    if not isinstance(v, bool):
                        raise ApiError(400, f"{k} is true or false")
                    v = int(v)
                elif col == "role":
                    if v not in ROLES:
                        raise ApiError(400, f"role is one of {', '.join(ROLES)}")
                    if d["role"] == "owner" and v != "owner" and self.owner_count() == 1:
                        raise ApiError(409, "this is the last owner device")
                elif col in ("speed_mbps", "quota_gb", "expires_at"):
                    if v is not None and (not isinstance(v, (int, float)) or isinstance(v, bool) or v <= 0):
                        raise ApiError(400, f"{k} is a positive number or null")
                sets[col] = v
            if d["role"] == "owner" and sets.get("enabled") == 0:
                raise ApiError(409, "the owner device cannot be disabled (revoke it instead)")
            if "expires_at" in sets and d["gone"] == "expired" and (sets["expires_at"] or 0) > now():
                sets["gone"] = None   # renewed by the owner
            if sets:
                self.db.x(f"UPDATE device SET {', '.join(c + '=?' for c in sets)} WHERE name=?", *sets.values(), name)
                log(f"patched {name}: {sets}")
                self.apply()
            return self.device(name)

    def owner_count(self) -> int:
        return self.db.one("SELECT COUNT(*) n FROM device WHERE role='owner'")["n"]

    def revoke(self, name: str) -> list[str]:
        with LOCK:
            d = self.device(name)
            if not d:
                raise ApiError(404, f"no device called '{name}'")
            if d["role"] == "owner" and self.owner_count() == 1:
                raise ApiError(409, "this is the last owner device")
            gone, todo = [], [name]
            while todo:
                n = todo.pop()
                if n in gone:
                    continue
                gone.append(n)
                todo += [r["name"] for r in self.db.q("SELECT name FROM device WHERE created_by=?", n)]
            for n in gone:
                for t in ("device", "usage", "session", "dns"):
                    self.db.x(f"DELETE FROM {t} WHERE name=?", n)
            log(f"revoked {gone}")
            self.apply()
            return gone

    def set_paused(self, p: bool):
        self.db.put("paused", bool(p))
        log("paused" if p else "resumed")
        self.apply()

    # ── config + link ──
    def client_conf(self, d) -> str:
        return (f"[Interface]\nPrivateKey = {d['priv']}\nAddress = {d['ip']}/32\nDNS = {SERVER_IP}\nMTU = {MTU}\n\n"
                f"[Peer]\nPublicKey = {self.server_pub()}\nPresharedKey = {d['psk']}\nEndpoint = {self.endpoint()}\n"
                f"AllowedIPs = 0.0.0.0/0, ::/0\nPersistentKeepalive = 25\n")

    def link(self, d) -> str:
        c = base64.urlsafe_b64encode(self.client_conf(d).encode()).decode().rstrip("=")
        return f"serdab://add?c={c}&n={d['name']}"

    # ── render kernel state from the database ──
    def apply(self):
        with LOCK:
            t = now()
            devs = self.devices()
            act = [d for d in devs if self.active(d, t)]
            sig = json.dumps([[d["pub"], d["ip"], d["filtered"], d["logged"], d["speed_mbps"]] for d in act])
            if sig == self.applied_sig:
                return
            conf = self.iface_block()
            for d in act:
                conf += f"\n# serdab:{d['name']}\n[Peer]\nPublicKey = {d['pub']}\nPresharedKey = {d['psk']}\nAllowedIPs = {d['ip']}/32\n"
            self.sys.sync_wg(conf, {d["pub"] for d in act})
            self.sys.nft(self.ruleset([d["ip"] for d in act if not d["filtered"]],
                                      [d["ip"] for d in act if not d["filtered"] and not d["logged"]]))
            self.sys.tc(self.tc_script([(d["ip"], d["speed_mbps"]) for d in act if d["speed_mbps"]]))
            self.applied_sig = sig
            log(f"applied: {len(act)} active of {len(devs)}")

    @staticmethod
    def ruleset(unfiltered: list[str], free: list[str] | None = None) -> str:
        """unfiltered: DNS without the family filter. free: may also use their
        own encrypted DNS (neither filtered nor logged: nothing to enforce)."""
        uf = ", ".join(unfiltered)
        fr = ", ".join(unfiltered if free is None else free)
        return f"""table ip serdab_ctl
delete table ip serdab_ctl
table ip serdab_ctl {{
  set unfiltered {{ type ipv4_addr; {"elements = { " + uf + " }" if uf else ""} }}
  set free {{ type ipv4_addr; {"elements = { " + fr + " }" if fr else ""} }}
  set doh {{ type ipv4_addr; flags interval; elements = {{ {", ".join(DOH_NETS)} }} }}
  set private {{ type ipv4_addr; flags interval; elements = {{ {", ".join(PRIVATE_NETS)} }} }}

  chain pre {{
    type nat hook prerouting priority dstnat; policy accept;
    iifname "{WG_IF}" ip saddr @unfiltered meta l4proto {{ tcp, udp }} th dport 53 dnat to {SERVER_IP}:5300
    iifname "{WG_IF}" meta l4proto {{ tcp, udp }} th dport 53 dnat to {SERVER_IP}:53
  }}
  chain input {{
    type filter hook input priority filter; policy accept;
    iifname "{WG_IF}" ip daddr {SERVER_IP} meta l4proto {{ tcp, udp }} th dport {{ 53, 5300 }} accept
    iifname "{WG_IF}" ip daddr {SERVER_IP} tcp dport {DEVICE_PORT} accept
    iifname "{WG_IF}" icmp type echo-request accept
    iifname "{WG_IF}" ct state established,related accept
    iifname "{WG_IF}" drop
  }}
  chain forward {{
    type filter hook forward priority filter; policy accept;
    iifname "{WG_IF}" ip daddr @private drop
    iifname "{WG_IF}" ip saddr @free accept
    iifname "{WG_IF}" tcp dport 853 reject with tcp reset
    iifname "{WG_IF}" udp dport 853 drop
    iifname "{WG_IF}" ip daddr @doh tcp dport 443 reject with tcp reset
    iifname "{WG_IF}" ip daddr @doh udp dport 443 drop
  }}
}}
"""

    @staticmethod
    def tc_script(caps: list[tuple[str, float]]) -> str:
        s = [f"tc qdisc del dev {WG_IF} root 2>/dev/null || true",
             f"tc qdisc del dev {WG_IF} ingress 2>/dev/null || true"]
        if caps:
            s += [f"tc qdisc add dev {WG_IF} root handle 1: htb default ffff",
                  f"tc class add dev {WG_IF} parent 1: classid 1:ffff htb rate 10gbit",
                  f"tc qdisc add dev {WG_IF} handle ffff: ingress"]
            for ip, mbps in caps:
                n = format(int(ip.split(".")[-1]), "x")
                rate = f"{int(mbps * 1000)}kbit"
                s += [f"tc class add dev {WG_IF} parent 1: classid 1:{n} htb rate {rate} ceil {rate}",
                      f"tc qdisc add dev {WG_IF} parent 1:{n} fq_codel",
                      f"tc filter add dev {WG_IF} parent 1: protocol ip prio 1 u32 match ip dst {ip}/32 flowid 1:{n}",
                      f"tc filter add dev {WG_IF} parent ffff: protocol ip prio 1 u32 match ip src {ip}/32 "
                      f"police rate {rate} burst 256k drop flowid :1"]
        return "\n".join(s) + "\n"

    # ── the tick: counters, sessions, expiry, quota ──
    def tick(self):
        with LOCK:
            t = now()
            peers = self.sys.dump()
            last = self.db.get("counters", {})
            new_last = {}
            for d in self.devices():
                p = peers.get(d["pub"])
                if not p:
                    continue
                prev = last.get(d["pub"], {"rx": 0, "tx": 0})
                rx = p["rx"] - prev["rx"] if p["rx"] >= prev["rx"] else p["rx"]
                tx = p["tx"] - prev["tx"] if p["tx"] >= prev["tx"] else p["tx"]
                new_last[d["pub"]] = {"rx": p["rx"], "tx": p["tx"]}
                if rx or tx:
                    self.db.x("INSERT INTO usage(name,day,down,up) VALUES(?,?,?,?) ON CONFLICT(name,day) DO UPDATE "
                              "SET down=down+excluded.down, up=up+excluded.up", d["name"], day_of(t), tx, rx)
                hs = p["hs"] or None
                if hs and hs != d["last_hs"]:
                    self.db.x("UPDATE device SET last_hs=?, first_hs=COALESCE(first_hs, ?) WHERE name=?", hs, hs, d["name"])
                online = bool(hs) and t - hs < ONLINE_WINDOW
                open_s = self.db.one("SELECT * FROM session WHERE name=? AND end IS NULL", d["name"])
                if online and not open_s:
                    self.db.x("INSERT INTO session(name,start,down,up) VALUES(?,?,?,?)", d["name"], hs, tx, rx)
                elif open_s and online:
                    self.db.x("UPDATE session SET down=down+?, up=up+? WHERE id=?", tx, rx, open_s["id"])
                elif open_s and not online:
                    self.db.x("UPDATE session SET end=?, down=down+?, up=up+? WHERE id=?",
                              d["last_hs"] or t, tx, rx, open_s["id"])
            # peers that left the kernel keep their old counters out of the next delta
            self.db.put("counters", new_last)
            # close sessions of devices no longer in the kernel
            for s in self.db.q("SELECT s.id, d.last_hs FROM session s JOIN device d ON d.name=s.name WHERE s.end IS NULL"):
                if not s["last_hs"] or t - s["last_hs"] >= ONLINE_WINDOW:
                    self.db.x("UPDATE session SET end=? WHERE id=?", s["last_hs"] or t, s["id"])
            # unused invitations die after 48 h, guests at their expiry
            for d in self.db.q("SELECT name FROM device WHERE first_hs IS NULL AND role!='owner' AND created_at<?",
                               t - PENDING_HOURS * 3600):
                for tb in ("device", "usage", "session", "dns"):
                    self.db.x(f"DELETE FROM {tb} WHERE name=?", d["name"])
                log(f"unused invitation {d['name']} removed")
            self.db.x("UPDATE device SET gone='expired' WHERE gone IS NULL AND expires_at IS NOT NULL AND expires_at<=?", t)
            self.apply()

    def prune(self):
        cutoff = (now() - LOG_DAYS * 86400) // 60
        self.db.x("DELETE FROM dns WHERE minute<?", cutoff)
        self.db.x("DELETE FROM usage WHERE day<?", day_of(now() - 400 * 86400))
        self.db.x("DELETE FROM session WHERE start<?", now() - 120 * 86400)

    # ── DNS log ingestion (dnsmasq log-queries=extra) ──
    # "Nov  8 12:00:01 dnsmasq[811]: 17 10.7.0.3/50123 query[A] www.example.com from 10.7.0.3"
    # "Nov  8 12:00:01 dnsmasq[811]: 17 10.7.0.3/50123 reply www.example.com is 0.0.0.0"
    LINE = re.compile(r"dnsmasq\[\d+\]: (\d+) ([\d.]+)/\d+ (query\[(?:A|AAAA|HTTPS)\]|reply|cached) (\S+) (?:from|is) (\S+)")

    def ingest_line(self, inst: str, line: str, t: int):
        m = self.LINE.search(line)
        if not m:
            return
        serial, ip, kind, domain, tail = m.groups()
        domain = domain.lower().rstrip(".")
        if kind.startswith("query"):
            self.qid[(inst, serial)] = (ip, domain)
            self.count_dns(ip, domain, t, blocked=False)
        elif tail in ("0.0.0.0", "::"):
            ip2, dom2 = self.qid.get((inst, serial), (ip, domain))
            self.count_dns(ip2, dom2, t, blocked=True)
        if len(self.qid) > 5000:
            self.qid.clear()

    def count_dns(self, ip, domain, t, blocked):
        d = self.by_ip.get(ip)
        if not d or not d["logged"]:
            return
        key = (d["name"], t // 60, domain)
        cur = self.dns_buf.setdefault(key, [0, 0])
        if blocked:
            cur[1] = 1
        else:
            cur[0] += 1

    def flush_dns(self):
        buf, self.dns_buf = self.dns_buf, {}
        for (name, minute, domain), (count, blocked) in buf.items():
            self.db.x("INSERT INTO dns(name,minute,domain,count,blocked) VALUES(?,?,?,?,?) ON CONFLICT(name,minute,domain) "
                      "DO UPDATE SET count=count+excluded.count, blocked=MAX(blocked, excluded.blocked)",
                      name, minute, domain, max(count, 1), blocked)

    @property
    def by_ip(self):
        if getattr(self, "_by_ip_at", 0) < time.time() - 10:
            self._by_ip = {d["ip"]: d for d in self.devices()}
            self._by_ip_at = time.time()
        return self._by_ip

    def tail_logs(self, stop: threading.Event):
        files = {inst: f"{LOG_DIR}/dns-{inst}.log" for inst in ("filtered", "open")}
        pos = {inst: (os.path.getsize(p) if os.path.exists(p) else 0) for inst, p in files.items()}
        while not stop.is_set():
            for inst, p in files.items():
                try:
                    size = os.path.getsize(p)
                except FileNotFoundError:
                    continue
                if size < pos[inst]:
                    pos[inst] = 0
                if size > pos[inst]:
                    with open(p, errors="replace") as f:
                        f.seek(pos[inst])
                        chunk = f.read(4 * 1024 * 1024)
                        pos[inst] = f.tell()
                    t = now()
                    for line in chunk.splitlines():
                        self.ingest_line(inst, line, t)
                    if pos[inst] > 20 * 1024 * 1024:     # dnsmasq appends (O_APPEND): truncating is safe
                        os.truncate(p, 0)
                        pos[inst] = 0
            self.flush_dns()
            stop.wait(5)


# ── HTTP ─────────────────────────────────────────────────────────────────────
class ApiError(Exception):
    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code, self.msg = code, msg


def admin_key() -> str:
    return open(f"{ETC}/admin.key").read().strip()


def make_handler(app: Serdab, kind: str):
    class H(BaseHTTPRequestHandler):
        server_version = "serdabd"
        sys_version = ""

        def log_message(self, fmt, *args):   # never log query strings or bodies
            pass

        def reply(self, code: int, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def body(self) -> dict:
            n = int(self.headers.get("Content-Length") or 0)
            if n > 65536:
                raise ApiError(413, "body too large")
            if not n:
                return {}
            try:
                b = json.loads(self.rfile.read(n))
            except ValueError:
                raise ApiError(400, "body is not JSON")
            if not isinstance(b, dict):
                raise ApiError(400, "body is a JSON object")
            return b

        def handle_any(self, method: str):
            try:
                u = urllib.parse.urlsplit(self.path)
                qs = dict(urllib.parse.parse_qsl(u.query))
                parts = [urllib.parse.unquote(p) for p in u.path.strip("/").split("/") if p]
                if kind == "admin":
                    auth = self.headers.get("Authorization", "")
                    if not hmac.compare_digest(auth.encode(), f"Bearer {admin_key()}".encode()):
                        time.sleep(1)
                        raise ApiError(401, "bad admin key")
                    out = admin_route(app, method, parts, qs, self.body if method in ("POST", "PATCH") else dict)
                else:
                    d = app.by_ip_fresh(self.client_address[0])
                    if not d:
                        raise ApiError(403, "this address is not a device")
                    out = device_route(app, d, method, parts, self.body if method == "POST" else dict)
                self.reply(200, out)
            except ApiError as e:
                self.reply(e.code, {"error": e.msg})
            except Exception as e:  # noqa: BLE001
                log(f"500 {method} {self.path.split('?')[0]}: {e!r}")
                self.reply(500, {"error": "internal error"})

        def do_GET(self):
            self.handle_any("GET")

        def do_POST(self):
            self.handle_any("POST")

        def do_PATCH(self):
            self.handle_any("PATCH")

        def do_DELETE(self):
            self.handle_any("DELETE")

    return H


def _by_ip_fresh(self: Serdab, ip: str):
    d = self.db.one("SELECT * FROM device WHERE ip=?", ip)
    return d if d and self.active(d) else None


Serdab.by_ip_fresh = _by_ip_fresh


def admin_route(app: Serdab, m: str, p: list[str], qs: dict, body):
    if p[:2] != ["admin", "v1"]:
        raise ApiError(404, "not found")
    p = p[2:]
    if m == "GET" and p == ["overview"]:
        devs = app.devices()
        t = now()
        sts = [app.status(d, t) for d in devs]
        today = app.db.one("SELECT COALESCE(SUM(down),0) d, COALESCE(SUM(up),0) u FROM usage WHERE day=?", day_of(t))
        month = app.db.one("SELECT COALESCE(SUM(down),0) d, COALESCE(SUM(up),0) u FROM usage WHERE day>=?", month_start(t))
        return {"ownerName": OWNER_NAME, "paused": app.paused(), "endpoint": app.endpoint(), "costPerGb": COST_PER_GB,
                "devices": {"total": len(devs), "online": sts.count("online")},
                "today": {"down": today["d"], "up": today["u"]},
                "month": {"down": month["d"], "up": month["u"],
                          "estCostUsd": round((month["d"] + month["u"]) / 1e9 * COST_PER_GB, 2)}}
    if m == "GET" and p == ["devices"]:
        return {"devices": [app.device_json(d) for d in app.devices()]}
    if m == "POST" and p == ["devices"]:
        b = body()
        d = app.create(b.get("name"), b.get("role"), "admin")
        return {"device": app.device_json(d), "link": app.link(d)}
    if m == "POST" and p == ["pause"]:
        b = body()
        if not isinstance(b.get("paused"), bool):
            raise ApiError(400, "paused is true or false")
        app.set_paused(b["paused"])
        return {"paused": app.paused()}
    if m == "GET" and p == ["blocked"]:
        lim = _int(qs.get("limit"), 100, 1, 500)
        rows = app.db.q("SELECT name, minute, domain, count FROM dns WHERE blocked=1 ORDER BY minute DESC LIMIT ?", lim)
        return {"blocked": [{"ts": r["minute"] * 60, "device": r["name"], "domain": r["domain"], "count": r["count"]} for r in rows]}
    if len(p) >= 2 and p[0] == "devices":
        d = app.device(p[1])
        if not d:
            raise ApiError(404, f"no device called '{p[1]}'")
        rest = p[2:]
        if m == "GET" and not rest:
            t = now()
            start = day_of(t - 29 * 86400)
            rows = {r["day"]: r for r in app.db.q("SELECT day, down, up FROM usage WHERE name=? AND day>=?", d["name"], start)}
            daily = []
            for i in range(29, -1, -1):
                k = day_of(t - i * 86400)
                r = rows.get(k)
                daily.append({"day": k, "down": r["down"] if r else 0, "up": r["up"] if r else 0})
            ss = app.db.q("SELECT start, end, down, up FROM session WHERE name=? ORDER BY start DESC LIMIT 50", d["name"])
            inv = [r["name"] for r in app.db.q("SELECT name FROM device WHERE created_by=?", d["name"])]
            return {"device": app.device_json(d), "daily": daily, "sessions": [dict(s) for s in ss], "invited": inv}
        if m == "PATCH" and not rest:
            return {"device": app.device_json(app.patch(d["name"], body()))}
        if m == "DELETE" and not rest:
            return {"revoked": app.revoke(d["name"])}
        if m == "GET" and rest == ["link"]:
            if app.status(d) == "expired":
                raise ApiError(410, "this device has expired")
            return {"link": app.link(d)}
        if m == "GET" and rest == ["domains"]:
            lim = _int(qs.get("limit"), 200, 1, 1000)
            sql, args = "SELECT minute, domain, count, blocked FROM dns WHERE name=?", [d["name"]]
            if qs.get("before"):
                sql += " AND minute<?"
                args.append(_int(qs["before"], 0, 0, 1 << 40) // 60)
            if qs.get("q"):
                sql += " AND domain LIKE ? ESCAPE '\\'"
                args.append("%" + re.sub(r"([%_\\])", r"\\\1", qs["q"].lower()) + "%")
            if qs.get("blocked") == "1":
                sql += " AND blocked=1"
            sql += " ORDER BY minute DESC, domain LIMIT ?"
            args.append(lim)
            rows = app.db.q(sql, *args)
            return {"logged": bool(d["logged"]),
                    "domains": [{"ts": r["minute"] * 60, "domain": r["domain"], "blocked": bool(r["blocked"]),
                                 "count": r["count"]} for r in rows]}
    raise ApiError(404, "not found")


def device_route(app: Serdab, d, m: str, p: list[str], body):
    if m == "GET" and p == ["v1", "me"]:
        md, mu = app.month_bytes(d["name"])
        return {"name": d["name"], "role": d["role"], "canShare": bool(d["can_share"]), "expiresAt": d["expires_at"],
                "filtered": bool(d["filtered"]), "monitored": bool(d["logged"]),
                "monthDown": md, "monthUp": mu,
                "quotaBytes": int(d["quota_gb"] * 1e9) if d["quota_gb"] is not None else None,
                "autoCloseMinutes": AUTO_CLOSE_MIN}
    if p == ["v1", "invites"]:
        if not d["can_share"]:
            raise ApiError(403, "this device cannot share")
        if m == "GET":
            rows = app.db.q("SELECT * FROM device WHERE created_by=? ORDER BY created_at DESC", d["name"])
            return {"invites": [{"name": r["name"], "createdAt": r["created_at"], "expiresAt": r["expires_at"],
                                 "status": app.status(r)} for r in rows]}
        if m == "POST":
            live = [r for r in app.db.q("SELECT * FROM device WHERE created_by=?", d["name"]) if app.status(r) != "expired"]
            if len(live) >= MAX_GUESTS_PER_SHARER:
                raise ApiError(429, f"{MAX_GUESTS_PER_SHARER} guests at a time")
            name = (body().get("name") or "")
            name = re.sub(r"[^a-z0-9-]+", "-", str(name).strip().lower()).strip("-")[:32]
            g = app.create(name, "guest", d["name"])
            return {"name": g["name"], "link": app.link(g), "expiresAt": g["expires_at"]}
    raise ApiError(404, "not found")


def _int(v, default, lo, hi):
    try:
        return max(lo, min(hi, int(v)))
    except (TypeError, ValueError):
        return default


# ── daemon ───────────────────────────────────────────────────────────────────
def serve():
    app = Serdab(DB(DB_PATH), Sys())
    app.adopt_legacy()
    app.apply()
    stop = threading.Event()
    servers = []
    for host in [SERVER_IP] if not FAKE else []:
        servers.append(ThreadingHTTPServer((host, DEVICE_PORT), make_handler(app, "device")))
    if FAKE:   # development: the device API on loopback (callers are matched by address, so only tests use it)
        servers.append(ThreadingHTTPServer((ENV("SERDAB_FAKE_DEVICE_HOST", "127.0.0.1"), DEVICE_PORT), make_handler(app, "device")))
    for host in ADMIN_HOSTS:
        servers.append(ThreadingHTTPServer((host, ADMIN_PORT), make_handler(app, "admin")))
    for s in servers:
        threading.Thread(target=s.serve_forever, daemon=True).start()
        log(f"listening on {s.server_address[0]}:{s.server_address[1]}")
    threading.Thread(target=app.tail_logs, args=(stop,), daemon=True).start()
    last_prune = 0
    while True:
        try:
            app.tick()
            if time.time() - last_prune > 3600:
                app.prune()
                last_prune = time.time()
        except Exception as e:  # noqa: BLE001
            log(f"tick failed: {e!r}")
        time.sleep(TICK)


# ── CLI (talks to the running daemon) ────────────────────────────────────────
def call(method, path, body=None):
    req = urllib.request.Request(f"http://127.0.0.1:{ADMIN_PORT}{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {admin_key()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"serdab: {json.loads(e.read()).get('error', e)}")
    except urllib.error.URLError:
        sys.exit("serdab: serdabd is not running (systemctl status serdabd)")


def human(n):
    for u in ("B", "KB", "MB", "GB", "TB"):
        if n < 1000 or u == "TB":
            return f"{n:.0f}{u}" if u == "B" else f"{n:.1f}{u}"
        n /= 1000


def ago(ts):
    if not ts:
        return "never"
    s = now() - ts
    return f"{s}s ago" if s < 60 else f"{s // 60}m ago" if s < 3600 else f"{s // 3600}h ago" if s < 86400 else f"{s // 86400}d ago"


USAGE = """serdab - your own tunnel.

  serdab add <device> [role]   enrol a device (role: owner, family, kid, guest; default family)
  serdab link <device>         its invitation link (send it in a chat; one tap sets the phone up)
  serdab qr <device>           its QR (for a phone in the same room)
  serdab conf <device>         its config file (a laptop, or the official WireGuard app)
  serdab rm <device>           revoke it, and every device it invited
  serdab disable|enable <device>
  serdab pause | resume        cut / restore everyone except the owner
  serdab list                  devices, status, traffic this month
"""


def cli(argv):
    cmd, arg = (argv + [None, None])[:2]
    if cmd == "add" and arg:
        r = call("POST", "/admin/v1/devices", {"name": arg, "role": (argv + [None, None, "family"])[2] or "family"})
        print(f"enrolled '{arg}' ({r['device']['role']}) at {r['device']['address']}\n")
        print("In the same room: scan this QR with the serdab app.\n")
        subprocess.run(["qrencode", "-t", "ansiutf8"], input=r["link"], text=True)
        print("\nFar away: send this link. It holds the device's private key: send it to that one person, then delete the message.\n")
        print(r["link"])
    elif cmd == "link" and arg:
        print(call("GET", f"/admin/v1/devices/{arg}/link")["link"])
    elif cmd == "qr" and arg:
        subprocess.run(["qrencode", "-t", "ansiutf8"], input=call("GET", f"/admin/v1/devices/{arg}/link")["link"], text=True)
    elif cmd == "conf" and arg:
        link = call("GET", f"/admin/v1/devices/{arg}/link")["link"]
        c = urllib.parse.parse_qs(urllib.parse.urlsplit(link).query)["c"][0]
        print(base64.urlsafe_b64decode(c + "=" * (-len(c) % 4)).decode(), end="")
    elif cmd == "rm" and arg:
        print("revoked", ", ".join(call("DELETE", f"/admin/v1/devices/{arg}")["revoked"]))
    elif cmd in ("disable", "enable") and arg:
        call("PATCH", f"/admin/v1/devices/{arg}", {"enabled": cmd == "enable"})
        print(f"{arg} {cmd}d")
    elif cmd in ("pause", "resume"):
        call("POST", "/admin/v1/pause", {"paused": cmd == "pause"})
        print("everyone except the owner is cut" if cmd == "pause" else "resumed")
    elif cmd in ("list", "ls"):
        ds = call("GET", "/admin/v1/devices")["devices"]
        print(f"{'DEVICE':16} {'ROLE':7} {'STATUS':10} {'ADDRESS':11} {'HANDSHAKE':10} {'MONTH':>9}  ENDS")
        for d in reversed(ds):
            u = d["usage"]
            ends = datetime.fromtimestamp(d["expiresAt"], TZ).strftime("%d %b") if d["expiresAt"] else ""
            print(f"{d['name']:16} {d['role']:7} {d['status']:10} {d['address']:11} {ago(d['lastHandshakeAt']):10} "
                  f"{human(u['monthDown'] + u['monthUp']):>9}  {ends}")
        if not ds:
            print("(no devices yet - serdab add <device>)")
    else:
        print(USAGE, end="")
        sys.exit(0 if cmd in (None, "help", "-h", "--help") else 1)


if __name__ == "__main__":
    if sys.argv[1:2] == ["serve"]:
        serve()
    else:
        cli(sys.argv[1:])
