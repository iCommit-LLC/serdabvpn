# serdab-dashboard

The console for a serdabVPN server: who is in the tunnel, what it costs, what
the family filter blocked, and the off switch. It talks to **serdabd**, the
service on the VPN VM, through its admin API (contract:
`serdabvpn/docs/api.md`).

What you can do from it:

- See every device: role, online/idle, last seen, month usage against its quota, guest expiry.
- Today and month traffic, and the estimated egress cost.
- **Pause all**: cut every device except the owner's, instantly. Resume brings them back.
- Per device: disable/enable, change role, sharing, filter, site history, quota, speed cap, guest expiry; revoke (with everything it invited).
- Site history (domains only, 30 days) for devices where it is on. Their app tells them it is on.
- Recent blocked lookups across all devices.
- New invitation (family, kid, guest) as a QR code and a link.

Next.js 16 App Router, React 19, Tailwind v4. Server components and server
actions only; the one client component is the copy button. Same shape as
icommit-dashboard.

## Auth

Login is the server's admin key (`/etc/serdab/admin.key` on the VM), checked
against `GET /admin/v1/overview` and kept in an httpOnly, `SameSite=Strict`
cookie. It never reaches browser JavaScript; every serdabd call is made on the
server with `Authorization: Bearer <key>`. A rejected key (rotated on the VM)
drops the cookie and returns to login.

## Env

| var | default | |
|---|---|---|
| `SERDAB_API` | `http://127.0.0.1:8801` | serdabd's admin listener. In prod the VM's private IP, `http://10.200.0.2:8801`. |
| `COOKIE_INSECURE` | unset | `1` only to test `npm run start` over plain http locally. |

## Local dev

```sh
npm install
npm run mock      # fake serdabd on :8801 with a family of fixtures, key: dev-key
npm run dev       # http://localhost:3000, log in with dev-key
```

The mock (`scripts/mock-api.mjs`, no deps) implements every admin endpoint
in memory: an owner phone, a wife (family) phone that invited two guests, a
son (kid) phone with site history and blocked lookups, an expired guest and an
unused invitation. Restart it to reset.

Checks: `npm run lint`, `npm run typecheck`, `npm run build`.

## Deploy

Push to `main` deploys (`.github/workflows/deploy.yml`): image to Artifact
Registry `europe-west1-docker.pkg.dev/<project>/icommit/serdab-dashboard`,
Cloud Run service `serdab-dashboard` in **europe-west9** (Paris, next to the
VM), direct VPC egress on the `default` network so it can reach the VM's
private address. serdabd's admin port is not exposed to the internet; a
firewall rule only lets the Paris subnet reach it.

Repo variables: `GCP_WIF_PROVIDER` (the org-wide GitHub provider, same value as
icommit-dashboard) and `GCP_DEPLOYER_SA` (`serdab-dashboard-deployer@…`). The
deployer and runtime service accounts and the firewall rule are created with
the serdab server setup, not here.
