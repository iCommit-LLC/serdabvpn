import { AutoSaveForm } from "@/components/AutoSaveForm";
import Link from "next/link";
import { notFound } from "next/navigation";
import { RoleBadge, StatusPill } from "@/components/Badges";
import { Flash } from "@/components/Flash";
import { Invitation } from "@/components/Invitation";
import { UsageChart } from "@/components/UsageChart";
import { ago, bytes, dateTime, day, duration, expiry, isoDay, nowSeconds } from "@/lib/format";
import { SerdabError, getDevice, getDomains, getLink } from "@/lib/server/serdab";
import { ROLES, type Device } from "@/lib/types";
import { revoke, saveSettings, setEnabled } from "../../actions";

type Search = Promise<{
  done?: string;
  error?: string;
  invite?: string;
  q?: string;
  blocked?: string;
  before?: string;
}>;

const PAGE = 100;

export default async function DevicePage({ params, searchParams }: { params: Promise<{ name: string }>; searchParams: Search }) {
  const { name: raw } = await params;
  const name = decodeURIComponent(raw);
  const sp = await searchParams;

  let detail;
  try {
    detail = await getDevice(name);
  } catch (e) {
    if (e instanceof SerdabError && e.status === 404) notFound();
    throw e;
  }
  const { device: d, daily, sessions, invited } = detail;
  const now = nowSeconds();

  const q = (sp.q ?? "").trim();
  const blockedOnly = sp.blocked === "1";
  const before = sp.before && /^\d+$/.test(sp.before) ? Number(sp.before) : undefined;
  const [domains, link] = await Promise.all([
    getDomains(name, { limit: PAGE, q: q || undefined, blocked: blockedOnly, before }),
    sp.invite === "1" ? getLink(name) : Promise.resolve(null),
  ]);

  const base = `/devices/${encodeURIComponent(name)}`;
  const exp = expiry(d.expiresAt, now);
  const month = d.usage.monthDown + d.usage.monthUp;
  const today = d.usage.todayDown + d.usage.todayUp;

  return (
    <main className="space-y-6">
      <Link href="/" className="text-sm text-muted hover:text-text">
        ← All devices
      </Link>

      <section className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="min-w-0 truncate font-serif text-4xl leading-tight">{d.name}</h1>
          <RoleBadge role={d.role} />
          <StatusPill status={d.status} />
        </div>
        <p className="text-sm text-muted">
          {d.address} · {d.createdBy === "admin" ? "added by you" : `invited by ${d.createdBy}`} {day(d.createdAt)}
          {exp ? ` · ${exp}` : ""} · {d.firstHandshakeAt ? `last seen ${ago(d.lastHandshakeAt, now)}` : "never connected"}
        </p>
      </section>

      <Flash
        done={sp.done}
        error={sp.error}
        messages={{
          saved: "Saved.",
          "logged-on": `Saved. Their app now says the sites visited on this connection are monitored (not by whom).`,
          enabled: "Enabled. They can connect again.",
          disabled: "Disabled. Their phone is cut off; the device and its history stay.",
          created: "Invitation ready.",
        }}
      />

      {link ? (
        <section className="card space-y-3 p-5">
          <div className="flex items-center justify-between gap-3">
            <h2 className="font-serif text-2xl">Invitation</h2>
            <Link href={base} className="text-sm text-muted hover:text-text">
              Hide
            </Link>
          </div>
          <Invitation name={d.name} link={link} />
        </section>
      ) : null}

      <section className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Mini label="Today" value={bytes(today)} />
        <Mini label="This month" value={bytes(month)} sub={d.quotaGb ? `of ${d.quotaGb} GB` : "no quota"} />
        <Mini label="Speed cap" value={d.speedMbps ? `${d.speedMbps} Mbps` : "none"} />
        <Mini label="Filter" value={d.filtered ? "on" : "off"} sub={d.logged ? "sites logged" : "sites not logged"} />
      </section>

      <div className="grid gap-6 lg:grid-cols-[1fr_22rem]">
        <div className="min-w-0 space-y-6">
          <section className="card space-y-3 p-5">
            <h2 className="font-serif text-2xl">Traffic</h2>
            <UsageChart daily={daily} />
          </section>

          <Sites device={d} base={base} q={q} blockedOnly={blockedOnly} before={before} domains={domains} />

          <section className="card space-y-3 p-5">
            <h2 className="font-serif text-2xl">Sessions</h2>
            {sessions.length === 0 ? (
              <p className="text-sm text-muted">No sessions yet.</p>
            ) : (
              <ul className="divide-y divide-line">
                {sessions.map((s) => (
                  <li key={s.start} className="flex items-center justify-between gap-3 py-2 text-sm">
                    <span className="min-w-0">
                      <span className="block">{dateTime(s.start)}</span>
                      <span className="text-xs text-muted">
                        {s.end ? duration(s.end - s.start) : <span className="text-ok">connected now · {duration(now - s.start)}</span>}
                      </span>
                    </span>
                    <span className="shrink-0 text-right text-xs text-muted">
                      {bytes(s.down)} down
                      <br />
                      {bytes(s.up)} up
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>

        <aside className="order-first min-w-0 space-y-6 lg:order-none">
          <section className="card space-y-3 p-5">
            <h2 className="font-serif text-2xl">Access</h2>
            {d.enabled ? (
              <details>
                <summary className="btn-danger w-full">Disable</summary>
                <form action={setEnabled} className="mt-3 space-y-2">
                  <input type="hidden" name="name" value={d.name} />
                  <input type="hidden" name="enabled" value="0" />
                  <p className="text-sm text-muted">Their phone loses the tunnel now. You can enable it again later.</p>
                  <button type="submit" className="btn-danger w-full">
                    Yes, disable {d.name}
                  </button>
                </form>
              </details>
            ) : (
              <form action={setEnabled}>
                <input type="hidden" name="name" value={d.name} />
                <input type="hidden" name="enabled" value="1" />
                <button type="submit" className="btn-primary w-full">
                  Enable
                </button>
              </form>
            )}
            {!link ? (
              <Link href={`${base}?invite=1`} className="btn-ghost w-full">
                Show invitation
              </Link>
            ) : null}
          </section>

          <Settings d={d} />

          <section className="card space-y-3 border-danger/40 p-5">
            <h2 className="font-serif text-2xl">Revoke</h2>
            <p className="text-sm text-muted">
              Deletes the device, its key and its history.
              {invited.length ? ` These go with it: ${invited.join(", ")}.` : " It invited no one."}
            </p>
            <details>
              <summary className="btn-danger w-full">Revoke {d.name}</summary>
              <form action={revoke} className="mt-3 space-y-2">
                <input type="hidden" name="name" value={d.name} />
                <p className="text-sm text-danger">
                  This cannot be undone{invited.length ? `, and ${invited.length} invited ${invited.length === 1 ? "device goes" : "devices go"} too` : ""}.
                </p>
                <button type="submit" className="btn-danger w-full">
                  Yes, revoke for good
                </button>
              </form>
            </details>
          </section>
        </aside>
      </div>
    </main>
  );
}

function Mini({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="card min-w-0 p-3">
      <p className="label">{label}</p>
      <p className="mt-1 truncate text-lg font-semibold">{value}</p>
      {sub ? <p className="truncate text-xs text-muted">{sub}</p> : null}
    </div>
  );
}

function Toggle({ name, label, help, checked }: { name: string; label: string; help: string; checked: boolean }) {
  return (
    <label className="flex cursor-pointer items-start gap-3">
      <input type="checkbox" name={name} defaultChecked={checked} className="peer sr-only" />
      <span className="relative mt-0.5 h-6 w-10 shrink-0 rounded-full bg-line-strong transition-colors peer-checked:bg-sand peer-focus-visible:ring-2 peer-focus-visible:ring-sand after:absolute after:top-0.5 after:left-0.5 after:size-5 after:rounded-full after:bg-bg after:transition-transform peer-checked:after:translate-x-4" />
      <span className="min-w-0">
        <span className="block text-sm font-medium">{label}</span>
        <span className="block text-xs text-muted">{help}</span>
      </span>
    </label>
  );
}

function Settings({ d }: { d: Device }) {
  const showExpiry = d.role === "guest" || d.expiresAt !== null;
  return (
    <AutoSaveForm action={saveSettings} className="card space-y-4 p-5">
      <h2 className="font-serif text-2xl">Rules</h2>
      <p className="text-xs text-muted">Switches and the role save as soon as you change them.</p>
      <input type="hidden" name="name" value={d.name} />
      <input type="hidden" name="wasLogged" value={d.logged ? "1" : "0"} />
      <label className="block">
        <span className="label">Role</span>
        <select name="role" defaultValue={d.role} className="field mt-2">
          {ROLES.map((r) => (
            <option key={r} value={r}>
              {r}
            </option>
          ))}
        </select>
      </label>
      <Toggle name="canShare" label="Can share" help="Can create guest invitations from their app." checked={d.canShare} />
      <Toggle name="filtered" label="Family filter" help="Adult and malware sites blocked; DNS forced through the server." checked={d.filtered} />
      <Toggle
        name="logged"
        label="Keep site history"
        help="Domains kept 30 days. When on, their app says the connection is monitored (not by whom)."
        checked={d.logged}
      />
      <div className="grid grid-cols-2 gap-3">
        <label className="block min-w-0">
          <span className="label">Quota GB/month</span>
          <input name="quotaGb" inputMode="numeric" defaultValue={d.quotaGb ?? ""} placeholder="none" className="field mt-2" />
        </label>
        <label className="block min-w-0">
          <span className="label">Speed Mbps</span>
          <input name="speedMbps" inputMode="numeric" defaultValue={d.speedMbps ?? ""} placeholder="none" className="field mt-2" />
        </label>
      </div>
      {showExpiry ? (
        <label className="block">
          <span className="label">Access ends</span>
          <input type="date" name="expiresAt" defaultValue={d.expiresAt ? isoDay(d.expiresAt) : ""} className="field mt-2" />
          <span className="mt-1 block text-xs text-muted">End of that day, Qatar time. Empty means never.</span>
        </label>
      ) : null}
      <button type="submit" className="btn-primary w-full">
        Save limits
      </button>
    </AutoSaveForm>
  );
}

function Sites({
  device: d,
  base,
  q,
  blockedOnly,
  before,
  domains,
}: {
  device: Device;
  base: string;
  q: string;
  blockedOnly: boolean;
  before?: number;
  domains: { logged: boolean; domains: { ts: number; domain: string; blocked: boolean; count: number }[] };
}) {
  const rows = domains.domains;
  const older = rows.length >= PAGE ? rows[rows.length - 1].ts : null;
  const qs = (extra: Record<string, string | undefined>) => {
    const p = new URLSearchParams();
    if (q) p.set("q", q);
    if (blockedOnly) p.set("blocked", "1");
    for (const [k, v] of Object.entries(extra)) {
      if (v === undefined) p.delete(k);
      else p.set(k, v);
    }
    const s = p.toString();
    return s ? `${base}?${s}#sites` : `${base}#sites`;
  };

  return (
    <section id="sites" className="card space-y-3 p-5">
      <h2 className="font-serif text-2xl">Sites</h2>
      {!d.logged && rows.length === 0 ? (
        <p className="text-sm text-muted">
          Site history is off for {d.name}. Turn on <span className="text-text">Keep site history</span> in Rules; their app will then tell
          them the connection is monitored, without naming you. You see domains (youtube.com), never pages or messages.
        </p>
      ) : (
        <>
          {!d.logged ? <p className="text-xs text-muted">History is off now; showing what was kept before.</p> : null}
          <form action={base} className="flex flex-wrap items-center gap-2">
            <input name="q" defaultValue={q} placeholder="Search a domain" className="field min-w-0 flex-1 basis-40" autoCapitalize="none" />
            <label className="flex items-center gap-2 text-sm text-muted">
              <input type="checkbox" name="blocked" value="1" defaultChecked={blockedOnly} className="accent-[var(--c-sand)]" />
              blocked only
            </label>
            <button type="submit" className="btn-ghost">
              Filter
            </button>
          </form>
          {rows.length === 0 ? (
            <p className="text-sm text-muted">{q || blockedOnly ? "Nothing matches." : "Nothing yet."}</p>
          ) : (
            <ul className="divide-y divide-line">
              {rows.map((r, i) => (
                <li key={`${r.ts}-${r.domain}-${i}`} className="flex items-center gap-3 py-2 text-sm">
                  <span className="w-24 shrink-0 text-xs text-muted">{dateTime(r.ts)}</span>
                  <span className={`min-w-0 flex-1 truncate font-mono text-[13px] ${r.blocked ? "text-danger" : ""}`}>{r.domain}</span>
                  {r.count > 1 ? <span className="shrink-0 text-xs text-muted">{r.count}×</span> : null}
                  {r.blocked ? (
                    <span className="shrink-0 rounded-md border border-danger/50 px-1.5 text-[11px] font-semibold text-danger uppercase">blocked</span>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
          <div className="flex justify-between gap-3 text-sm">
            {before ? (
              <Link href={qs({ before: undefined })} className="text-muted hover:text-text">
                ← Newest
              </Link>
            ) : (
              <span />
            )}
            {older ? (
              <Link href={qs({ before: String(older) })} className="text-sand hover:text-lamp">
                Older →
              </Link>
            ) : null}
          </div>
        </>
      )}
    </section>
  );
}
