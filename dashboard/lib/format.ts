// Display helpers. Times are shown in the family's time zone: SERDAB_TZ
// (an IANA name such as Europe/Paris or Asia/Qatar), UTC when unset.

export const TZ = process.env.SERDAB_TZ || "UTC";

export function bytes(n: number): string {
  if (!Number.isFinite(n) || n <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  let v = n;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  const digits = v >= 100 || i === 0 ? 0 : v >= 10 ? 1 : 2;
  return `${v.toFixed(digits)} ${units[i]}`;
}

export function usd(n: number): string {
  return `$${n.toFixed(n < 100 ? 2 : 0)}`;
}

/** "29 Nov" */
export function day(ts: number): string {
  return new Intl.DateTimeFormat("en-GB", { timeZone: TZ, day: "numeric", month: "short" }).format(
    ts * 1000,
  );
}

/** "29 Nov, 14:02" */
export function dateTime(ts: number): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: TZ,
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(ts * 1000);
}

/** "3 min ago" / "2 h ago" / "4 days ago" / "never" */
export function ago(ts: number | null, now = Date.now() / 1000): string {
  if (!ts) return "never";
  const s = Math.max(0, Math.round(now - ts));
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  const d = Math.floor(s / 86400);
  return d === 1 ? "yesterday" : `${d} days ago`;
}

export function duration(seconds: number): string {
  const m = Math.max(1, Math.round(seconds / 60));
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r ? `${h} h ${r} min` : `${h} h`;
}

/** Expiry as shown on a device: "ends 29 Nov", "expired 2 Nov", or "". */
export function expiry(expiresAt: number | null, now = Date.now() / 1000): string {
  if (!expiresAt) return "";
  return expiresAt > now ? `ends ${day(expiresAt)}` : `expired ${day(expiresAt)}`;
}

/** YYYY-MM-DD of a timestamp in TZ, for <input type="date">. */
export function isoDay(ts: number): string {
  // en-CA formats dates as YYYY-MM-DD.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ts * 1000);
}

/** Minutes TZ is ahead of UTC at a given instant (DST-aware). */
function offsetMinutes(ms: number): number {
  const name = new Intl.DateTimeFormat("en-US", { timeZone: TZ, timeZoneName: "longOffset" })
    .formatToParts(ms)
    .find((p) => p.type === "timeZoneName")?.value ?? "GMT";
  const m = /GMT([+-])(\d{2}):?(\d{2})?/.exec(name);
  return m ? (m[1] === "-" ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3] ?? 0)) : 0;
}

/** End of that day (23:59:59) in TZ, as unix seconds. */
export function endOfDay(iso: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return null;
  const asUtc = Date.UTC(+m[1], +m[2] - 1, +m[3], 23, 59, 59);
  return Math.floor((asUtc - offsetMinutes(asUtc) * 60_000) / 1000);
}
/** Request time in unix seconds. Server components render once per request, so this is stable. */
export function nowSeconds(): number {
  return Date.now() / 1000;
}
