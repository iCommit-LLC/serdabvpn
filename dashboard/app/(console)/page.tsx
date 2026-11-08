import Link from "next/link";
import { RoleBadge, StatusPill } from "@/components/Badges";
import { Flash } from "@/components/Flash";
import { ago, bytes, dateTime, expiry, nowSeconds, usd } from "@/lib/format";
import { getBlocked, getOverview, listDevices } from "@/lib/server/serdab";
import type { Device } from "@/lib/types";
import { pauseAll } from "./actions";

type Search = Promise<{ done?: string; error?: string; names?: string }>;

export default async function OverviewPage({ searchParams }: { searchParams: Search }) {
  const { done, error, names } = await searchParams;
  const [ov, devices, blocked] = await Promise.all([getOverview(), listDevices(), getBlocked(8)]);
  const now = nowSeconds();

  const active = devices.filter((d) => d.status !== "expired");
  const expired = devices.filter((d) => d.status === "expired");

  return (
    <main className="space-y-6">
      <Flash
        done={done}
        error={error}
        messages={{
          paused: `Paused. Only ${ov.ownerName}'s devices can connect.`,
          resumed: "Resumed. Everyone can connect again.",
          revoked: `Revoked: ${(names ?? "").split(",").filter(Boolean).join(", ") || "done"}.`,
        }}
      />

      {ov.paused ? (
        <section className="card flex flex-col gap-3 border-amber/60 bg-amber/10 p-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="font-semibold text-amber">Everyone is paused</p>
            <p className="text-sm text-muted">Only {ov.ownerName}&apos;s devices can connect until you resume.</p>
          </div>
          <form action={pauseAll}>
            <input type="hidden" name="paused" value="0" />
            <button type="submit" className="btn-primary w-full sm:w-auto">
              Resume everyone
            </button>
          </form>
        </section>
      ) : null}

      <section className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Online now" value={`${ov.devices.online}`} sub={`of ${ov.devices.total} devices`} />
        <Stat label="Today" value={bytes(ov.today.down + ov.today.up)} sub={`${bytes(ov.today.down)} down · ${bytes(ov.today.up)} up`} />
        <Stat label="This month" value={bytes(ov.month.down + ov.month.up)} sub={`${bytes(ov.month.down)} down · ${bytes(ov.month.up)} up`} />
        <Stat label="Month cost, est." value={usd(ov.month.estCostUsd)} sub={`egress at ${usd(ov.costPerGb)}/GB`} accent />
      </section>

      <section className="space-y-3">
        <div className="flex items-end justify-between gap-3">
          <h2 className="font-serif text-2xl">Devices</h2>
          {!ov.paused ? (
            <details className="group relative">
              <summary className="btn-danger">Pause all</summary>
              <div className="card absolute right-0 z-10 mt-2 w-72 space-y-3 p-4 shadow-xl">
                <p className="text-sm">
                  Cut every device except {ov.ownerName}&apos;s, right now. Nothing is deleted; resume brings them back.
                </p>
                <form action={pauseAll}>
                  <input type="hidden" name="paused" value="1" />
                  <button type="submit" className="btn-danger w-full">
                    Yes, pause everyone
                  </button>
                </form>
              </div>
            </details>
          ) : null}
        </div>

        {active.length === 0 ? (
          <p className="card p-5 text-sm text-muted">
            No devices yet. <Link className="text-sand underline" href="/invite">Make an invitation</Link>.
          </p>
        ) : (
          <ul className="card divide-y divide-line overflow-hidden">
            {active.map((d) => (
              <DeviceRow key={d.name} d={d} now={now} />
            ))}
          </ul>
        )}

        {expired.length ? (
          <details className="card overflow-hidden">
            <summary className="cursor-pointer px-4 py-3 text-sm text-muted hover:text-text">
              {expired.length} expired {expired.length === 1 ? "guest" : "guests"}
            </summary>
            <ul className="divide-y divide-line border-t border-line">
              {expired.map((d) => (
                <DeviceRow key={d.name} d={d} now={now} />
              ))}
            </ul>
          </details>
        ) : null}
      </section>

      <section className="space-y-3">
        <h2 className="font-serif text-2xl">Recent blocked</h2>
        {blocked.length === 0 ? (
          <p className="card p-5 text-sm text-muted">Nothing blocked recently.</p>
        ) : (
          <ul className="card divide-y divide-line overflow-hidden">
            {blocked.map((b, i) => (
              <li key={`${b.ts}-${b.device}-${b.domain}-${i}`} className="flex items-center gap-3 px-4 py-2.5 text-sm">
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-mono text-danger">{b.domain}</span>
                  <span className="text-xs text-muted">
                    <Link href={`/devices/${encodeURIComponent(b.device)}?blocked=1`} className="hover:text-text">
                      {b.device}
                    </Link>{" "}
                    · {dateTime(b.ts)}
                    {b.count > 1 ? ` · ${b.count}×` : ""}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <p className="text-center text-xs text-muted">Tunnel endpoint {ov.endpoint}</p>
    </main>
  );
}

function Stat({ label, value, sub, accent }: { label: string; value: string; sub: string; accent?: boolean }) {
  return (
    <div className="card min-w-0 p-4">
      <p className="label">{label}</p>
      <p className={`mt-1 truncate text-2xl font-semibold ${accent ? "text-amber" : ""}`}>{value}</p>
      <p className="mt-0.5 truncate text-xs text-muted">{sub}</p>
    </div>
  );
}

function DeviceRow({ d, now }: { d: Device; now: number }) {
  const month = d.usage.monthDown + d.usage.monthUp;
  const exp = expiry(d.expiresAt, now);
  return (
    <li>
      <Link href={`/devices/${encodeURIComponent(d.name)}`} className="flex items-center gap-3 px-4 py-3 hover:bg-inset">
        <div className="min-w-0 flex-1">
          <div className="flex min-w-0 flex-wrap items-center gap-2">
            <span className="truncate font-medium">{d.name}</span>
            <RoleBadge role={d.role} />
          </div>
          <p className="mt-0.5 truncate text-xs text-muted">
            {d.status === "pending" ? `invited ${ago(d.createdAt, now)}` : `seen ${ago(d.lastHandshakeAt, now)}`}
            {exp ? ` · ${exp}` : ""}
            {d.createdBy !== "admin" ? ` · by ${d.createdBy}` : ""}
          </p>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-1">
          <StatusPill status={d.status} />
          <span className="text-xs text-muted">
            {bytes(month)}
            {d.quotaGb ? ` / ${d.quotaGb} GB` : ""}
          </span>
        </div>
      </Link>
    </li>
  );
}
