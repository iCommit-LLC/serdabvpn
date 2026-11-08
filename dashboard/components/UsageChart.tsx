import { bytes } from "@/lib/format";
import type { DailyUsage } from "@/lib/types";

/** 30 days of traffic as stacked bars (down in amber, up in sand), plain SVG. */
export function UsageChart({ daily }: { daily: DailyUsage[] }) {
  const days = daily.slice(-30);
  const max = Math.max(1, ...days.map((d) => d.down + d.up));
  const W = 300;
  const H = 96;
  const slot = W / Math.max(days.length, 1);
  const bar = Math.max(2, slot - 2);
  const total = days.reduce((s, d) => s + d.down + d.up, 0);
  const peak = days.reduce((p, d) => (d.down + d.up > p.down + p.up ? d : p), days[0] ?? { day: "", down: 0, up: 0 });

  if (days.length === 0) return <p className="text-sm text-muted">No traffic yet.</p>;

  return (
    <figure className="space-y-2">
      <svg viewBox={`0 0 ${W} ${H}`} className="h-28 w-full" preserveAspectRatio="none" role="img" aria-label="Daily traffic, last 30 days">
        {days.map((d, i) => {
          const hDown = ((d.down / max) * (H - 4)) | 0;
          const hUp = ((d.up / max) * (H - 4)) | 0;
          const x = i * slot + (slot - bar) / 2;
          return (
            <g key={d.day}>
              <title>{`${d.day}: ${bytes(d.down)} down, ${bytes(d.up)} up`}</title>
              <rect x={x} y={H - hDown} width={bar} height={hDown} rx={1} fill="var(--c-amber)" />
              <rect x={x} y={H - hDown - hUp} width={bar} height={hUp} rx={1} fill="var(--c-sand)" fillOpacity={0.45} />
            </g>
          );
        })}
        <line x1="0" x2={W} y1={H - 0.5} y2={H - 0.5} stroke="var(--c-line-strong)" />
      </svg>
      <figcaption className="flex flex-wrap justify-between gap-x-4 gap-y-1 text-xs text-muted">
        <span>
          <span className="mr-1 inline-block size-2 rounded-sm bg-amber" />
          down
          <span className="mr-1 ml-3 inline-block size-2 rounded-sm bg-sand/45" />
          up
        </span>
        <span>
          30 days: <span className="text-text">{bytes(total)}</span>
          {peak && peak.down + peak.up > 0 ? (
            <>
              {" "}· peak {peak.day.slice(5)}: <span className="text-text">{bytes(peak.down + peak.up)}</span>
            </>
          ) : null}
        </span>
      </figcaption>
    </figure>
  );
}
