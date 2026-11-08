# serdabd API (contract)

serdabd runs on the VPN server. It owns the devices (WireGuard peers), their
rules, the DNS filter and the logs. SQLite at `/var/lib/serdab/serdab.db`.
Two listeners, two kinds of caller:

| Listener | Who | Auth |
|---|---|---|
| `10.7.0.1:8800` (inside the tunnel) | the phones | the source address: WireGuard only lets the holder of a peer's key send from its /32, so `10.7.0.5` *is* that device |
| `<vm internal ip>:8801` (GCP private network, e.g. `10.200.0.2`) | the dashboard on Cloud Run (direct VPC egress) | `Authorization: Bearer <admin key>` (`/etc/serdab/admin.key`) |

JSON in and out. Times are unix seconds (int). Bytes are ints. "down" = to the
phone, "up" = from the phone. Errors: HTTP 4xx/5xx with `{"error": "<message>"}`.

## Roles and their defaults

| role | who | canShare | filtered | logged | expires | quotaGb | speedMbps |
|---|---|---|---|---|---|---|---|
| `owner` | Taha | yes | no | no | never | none | none |
| `family` | Taha's wife | yes (guests only) | yes | yes | never | none | none |
| `kid` | the son | no | yes | yes | never | none | none |
| `guest` | anyone a family member invites | no | yes | no | 21 days after the invitation is created | 30 | 5 |

- Only `owner` can create `family`/`kid` devices (dashboard or CLI). `owner` and
  `family` can create `guest` devices from the app.
- A guest invitation never used within 48 h is removed.
- `filtered`: DNS goes through Cloudflare for Families (adult + malware blocked),
  port 53 is forced to the server, DoT (853) and known DoH endpoints are blocked.
- `logged`: the domains this device looks up are kept 30 days and shown in the
  dashboard. The app tells the device's user that the connection is monitored
  (`monitored`), never by whom.
- Revoking a device also revokes every device it invited.
- `paused` (server-wide): every device except `owner` is cut until resumed.

## Device object

```json
{
  "name": "mom",
  "role": "family",
  "address": "10.7.0.3",
  "status": "online",
  "enabled": true,
  "canShare": true,
  "filtered": true,
  "logged": true,
  "speedMbps": null,
  "quotaGb": null,
  "createdAt": 1762600000,
  "createdBy": "admin",
  "expiresAt": null,
  "firstHandshakeAt": 1762600100,
  "lastHandshakeAt": 1762610000,
  "usage": { "todayDown": 0, "todayUp": 0, "monthDown": 0, "monthUp": 0 }
}
```

`status`, first match wins: `disabled` (enabled=false), `expired`, `paused`
(server paused and not owner), `over_quota`, `pending` (never handshaked),
`online` (handshake < 3 min ago), `idle`.

`createdBy` is `"admin"` (dashboard/CLI) or the inviting device's name.

## Admin API (`:8801`, bearer)

| | | |
|---|---|---|
| `GET /admin/v1/overview` | | `{ownerName, paused, endpoint, costPerGb, devices:{total, online}, today:{down, up}, month:{down, up, estCostUsd}}` |
| `GET /admin/v1/devices` | | `{devices: [Device]}` (newest first, expired included) |
| `GET /admin/v1/devices/{name}` | | `{device, daily: [{day: "2026-11-08", down, up}] (30 days, oldest first), sessions: [{start, end: int|null, down, up}] (latest 50), invited: [name]}` |
| `GET /admin/v1/devices/{name}/domains` | `?limit=200&before=<ts>&q=<substring>&blocked=1` | `{logged, domains: [{ts, domain, blocked, count}]}` newest first; `count` = lookups in that minute |
| `GET /admin/v1/blocked` | `?limit=100` | `{blocked: [{ts, device, domain, count}]}` across all devices |
| `POST /admin/v1/devices` | `{name, role}` | `{device, link}`; name = `^[a-z0-9][a-z0-9-]{0,31}$` |
| `PATCH /admin/v1/devices/{name}` | any of `{enabled, role, canShare, filtered, logged, speedMbps, quotaGb, expiresAt}` (`null` clears a limit) | `{device}` |
| `DELETE /admin/v1/devices/{name}` | | `{revoked: [name]}` (the device and everything it invited) |
| `GET /admin/v1/devices/{name}/link` | | `{link}` (holds the private key: show, do not log) |
| `POST /admin/v1/pause` | `{paused: bool}` | `{paused}` |

`link` is `serdab://add?c=<base64url(wg-quick config)>&n=<name>`, what the app
already reads (`app/lib/invite.dart`); render it as a QR.

## Device API (`10.7.0.1:8800`, inside the tunnel)

| | | |
|---|---|---|
| `GET /v1/me` | | `{name, role, canShare, expiresAt, filtered, monitored: bool, monthDown, monthUp, quotaBytes: int|null, autoCloseMinutes: 120}` (never names who monitors) |
| `POST /v1/invites` | `{name}` | `{name, link, joinUrl, expiresAt}`; 403 unless `canShare`; always role `guest`. `joinUrl` (when `SERDAB_JOIN_URL` is set) is the tappable https form for chats: `<dashboard>/join#c=...&n=...` |
| `GET /v1/invites` | | `{invites: [{name, createdAt, expiresAt, status}]}` the caller's guests |
