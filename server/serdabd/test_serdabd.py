"""Fake-mode tests: no wg, nft or tc. Run: python3 -m unittest test_serdabd -v"""
import json, os, re, tempfile, threading, unittest, urllib.request, urllib.error

ROOT = tempfile.mkdtemp(prefix="serdabd-")
os.environ.update(SERDAB_FAKE="1", SERDAB_ROOT=ROOT, SERDAB_ADMIN_PORT="18801", SERDAB_DEVICE_PORT="18800", SERDAB_TICK="3600")
os.makedirs(ROOT + "/etc/serdab"); open(ROOT + "/etc/serdab/admin.key", "w").write("k" * 40)
os.makedirs(ROOT + "/etc/wireguard/clients")
open(ROOT + "/etc/wireguard/server.pub", "w").write("SERVERPUB=\n")
open(ROOT + "/etc/wireguard/endpoint", "w").write("34.163.198.164:51820\n")
open(ROOT + "/etc/wireguard/wg0.conf", "w").write("[Interface]\nAddress = 10.7.0.1/24\nListenPort = 51820\nPostUp = nft add table ip serdab\n\n# serdab:phone\n[Peer]\nPublicKey = X\nAllowedIPs = 10.7.0.2/32\n")
open(ROOT + "/etc/wireguard/clients/phone.conf", "w").write("[Interface]\nPrivateKey = aaaa\nAddress = 10.7.0.2/32\n\n[Peer]\nPresharedKey = bbbb\n")

import serdabd as S

app = S.Serdab(S.DB(S.DB_PATH), S.Sys())
app.adopt_legacy(); app.apply()
srv = S.ThreadingHTTPServer(("127.0.0.1", 18801), S.make_handler(app, "admin"))
threading.Thread(target=srv.serve_forever, daemon=True).start()

def call(m, path, body=None, key="k" * 40):
    r = urllib.request.Request("http://127.0.0.1:18801" + path, method=m, data=json.dumps(body).encode() if body is not None else None,
                               headers={"Authorization": "Bearer " + key})
    try:
        with urllib.request.urlopen(r) as x: return x.status, json.loads(x.read())
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read())

def me(name): return app.device(name)
def wgconf(): return open(ROOT + "/etc/wireguard/wg0.conf").read()

class T(unittest.TestCase):
    def test_00_legacy_adopted_as_owner(self):
        d = me("phone"); self.assertEqual((d["role"], d["ip"], d["priv"]), ("owner", "10.7.0.2", "aaaa"))
        self.assertIn("PostUp = nft add table ip serdab", wgconf()); self.assertIn("# serdab:phone", wgconf())

    def test_01_bad_key(self):
        self.assertEqual(call("GET", "/admin/v1/overview", key="nope")[0], 401)

    def test_02_create_roles_and_link(self):
        c, r = call("POST", "/admin/v1/devices", {"name": "wife", "role": "family"}); self.assertEqual(c, 200, r)
        self.assertEqual(r["device"]["status"], "pending"); self.assertTrue(r["device"]["logged"])
        self.assertTrue(r["link"].startswith("serdab://add?c=")); self.assertTrue(r["link"].endswith("&n=wife"))
        c, r = call("POST", "/admin/v1/devices", {"name": "son", "role": "kid"}); self.assertFalse(r["device"]["canShare"])
        self.assertEqual(call("POST", "/admin/v1/devices", {"name": "wife", "role": "family"})[0], 409)
        self.assertEqual(call("POST", "/admin/v1/devices", {"name": "Bad Name", "role": "family"})[0], 400)
        self.assertEqual(call("POST", "/admin/v1/devices", {"name": "x", "role": "god"})[0], 400)
        conf = S.base64.urlsafe_b64decode(re.search(r"c=([^&]+)", r["link"]).group(1) + "==").decode()
        self.assertIn("DNS = 10.7.0.1", conf); self.assertIn("Endpoint = 34.163.198.164:51820", conf)

    def test_03_device_api_share(self):
        out = S.device_route(app, me("wife"), "POST", ["v1", "invites"], lambda: {"name": "Aunt Salma"})
        self.assertEqual(out["name"], "aunt-salma")
        g = me("aunt-salma"); self.assertEqual((g["role"], g["created_by"], g["quota_gb"], g["speed_mbps"]), ("guest", "wife", 30, 5))
        self.assertAlmostEqual(g["expires_at"] - g["created_at"], 21 * 86400, delta=2)
        with self.assertRaises(S.ApiError) as e:
            S.device_route(app, me("son"), "POST", ["v1", "invites"], lambda: {"name": "friend"})
        self.assertEqual(e.exception.code, 403)
        m = S.device_route(app, me("son"), "GET", ["v1", "me"], dict)
        self.assertEqual((m["monitored"], m["canShare"], m["autoCloseMinutes"]), (True, False, 120))
        self.assertNotIn("Taha", json.dumps(m))          # the device is never told who watches
        self.assertFalse(S.device_route(app, me("phone"), "GET", ["v1", "me"], dict)["monitored"])

    def test_04_traffic_sessions_quota(self):
        sx = app.sys; g = me("aunt-salma"); t = S.now()
        sx.fake_peers[g["pub"]] = {"hs": t - 5, "rx": 1_000_000, "tx": 9_000_000}
        app.tick()
        r = call("GET", "/admin/v1/devices/aunt-salma")[1]
        self.assertEqual(r["device"]["status"], "online"); self.assertEqual(r["device"]["usage"]["monthDown"], 9_000_000)
        self.assertEqual(len(r["sessions"]), 1); self.assertIsNone(r["sessions"][0]["end"])
        sx.fake_peers[g["pub"]] = {"hs": t - 4, "rx": 10, "tx": 20}; app.tick()   # wg restarted: counters reset
        self.assertEqual(call("GET", "/admin/v1/devices/aunt-salma")[1]["device"]["usage"]["monthDown"], 9_000_020)
        sx.fake_peers[g["pub"]] = {"hs": t - 3, "rx": 10, "tx": 31_000_000_020}; app.tick()
        self.assertEqual(app.status(me("aunt-salma")), "over_quota"); self.assertNotIn("# serdab:aunt-salma", wgconf())
        self.assertGreater(call("GET", "/admin/v1/overview")[1]["month"]["estCostUsd"], 3.7)
        call("PATCH", "/admin/v1/devices/aunt-salma", {"quotaGb": None}); self.assertIn("# serdab:aunt-salma", wgconf())

    def test_05_speed_and_filter_rendered(self):
        tc = open(ROOT + "/etc/serdab/tc.sh").read(); ip = me("aunt-salma")["ip"]
        self.assertIn(f"match ip dst {ip}/32", tc); self.assertIn("rate 5000kbit", tc)
        nft = open(ROOT + "/etc/serdab/rules.nft").read()
        self.assertIn("elements = { 10.7.0.2 }", nft); self.assertIn("169.254.0.0/16", nft)
        self.assertIn("@free accept", nft)

    def test_05b_logged_owner_loses_doh(self):
        call("PATCH", "/admin/v1/devices/phone", {"logged": True})
        nft = open(ROOT + "/etc/serdab/rules.nft").read()
        self.assertIn("set unfiltered { type ipv4_addr; elements = { 10.7.0.2 } }", nft)   # still no family filter
        self.assertIn("set free { type ipv4_addr;  }", nft)                             # but no DoH escape
        call("PATCH", "/admin/v1/devices/phone", {"logged": False})
        self.assertIn("set free { type ipv4_addr; elements = { 10.7.0.2 } }", open(ROOT + "/etc/serdab/rules.nft").read())

    def test_06_dns_log(self):
        ip = me("son")["ip"]
        for l in [f"Nov  8 12:00:01 dnsmasq[9]: 17 {ip}/5000 query[A] www.YouTube.com from {ip}",
                  f"Nov  8 12:00:01 dnsmasq[9]: 18 {ip}/5001 query[A] bad.example from {ip}",
                  f"Nov  8 12:00:01 dnsmasq[9]: 18 {ip}/5001 reply bad.example is 0.0.0.0",
                  "Nov  8 12:00:01 dnsmasq[9]: 19 10.7.0.2/5002 query[A] owner-secret.example from 10.7.0.2"]:
            app.ingest_line("filtered", l, S.now())
        app.flush_dns()
        doms = call("GET", "/admin/v1/devices/son/domains")[1]
        self.assertEqual({d["domain"]: d["blocked"] for d in doms["domains"]}, {"www.youtube.com": False, "bad.example": True})
        self.assertEqual(call("GET", "/admin/v1/devices/phone/domains")[1]["domains"], [])
        self.assertEqual(call("GET", "/admin/v1/blocked")[1]["blocked"][0]["domain"], "bad.example")
        self.assertEqual(len(call("GET", "/admin/v1/devices/son/domains?q=tube")[1]["domains"]), 1)
        self.assertEqual(len(call("GET", "/admin/v1/devices/son/domains?q=%25")[1]["domains"]), 0)

    def test_07_pause(self):
        call("POST", "/admin/v1/pause", {"paused": True})
        self.assertIn("# serdab:phone", wgconf()); self.assertNotIn("# serdab:son", wgconf())
        call("POST", "/admin/v1/pause", {"paused": False}); self.assertIn("# serdab:son", wgconf())

    def test_08_owner_guards(self):
        self.assertEqual(call("PATCH", "/admin/v1/devices/phone", {"enabled": False})[0], 409)
        self.assertEqual(call("DELETE", "/admin/v1/devices/phone")[0], 409)
        self.assertEqual(call("PATCH", "/admin/v1/devices/son", {"bogus": 1})[0], 400)

    def test_09_expiry_and_pending(self):
        app.db.x("UPDATE device SET expires_at=? WHERE name='aunt-salma'", S.now() - 1)
        app.tick(); self.assertEqual(app.status(me("aunt-salma")), "expired"); self.assertNotIn("# serdab:aunt-salma", wgconf())
        self.assertEqual(call("GET", "/admin/v1/devices/aunt-salma/link")[0], 410)
        app.db.x("UPDATE device SET created_at=? WHERE name='son'", S.now() - 49 * 3600)
        app.tick(); self.assertIsNone(me("son"))

    def test_10_revoke_cascades(self):
        S.device_route(app, me("wife"), "POST", ["v1", "invites"], lambda: {"name": "cousin"})
        c, r = call("DELETE", "/admin/v1/devices/wife")
        self.assertEqual(c, 200); self.assertEqual(set(r["revoked"]), {"wife", "aunt-salma", "cousin"})

if __name__ == "__main__":
    unittest.main()
