import type { Role, Status } from "@/lib/types";

const STATUS: Record<Status, { label: string; cls: string }> = {
  online: { label: "online", cls: "border-ok/50 text-ok" },
  idle: { label: "idle", cls: "border-line-strong text-muted" },
  pending: { label: "not used yet", cls: "border-amber/50 text-amber" },
  over_quota: { label: "over quota", cls: "border-danger/60 text-danger" },
  paused: { label: "paused", cls: "border-amber/50 text-amber" },
  expired: { label: "expired", cls: "border-line-strong text-muted" },
  disabled: { label: "disabled", cls: "border-danger/60 text-danger" },
};

export function StatusPill({ status }: { status: Status }) {
  const s = STATUS[status] ?? { label: status, cls: "border-line-strong text-muted" };
  return (
    <span
      className={`inline-flex shrink-0 items-center gap-1.5 rounded-full border px-2 py-0.5 text-xs font-medium ${s.cls}`}
    >
      {status === "online" ? <span className="size-1.5 rounded-full bg-ok" /> : null}
      {s.label}
    </span>
  );
}

const ROLE: Record<Role, string> = {
  owner: "bg-sand text-on-sand",
  family: "bg-amber/15 text-amber",
  kid: "bg-lamp/15 text-lamp",
  guest: "bg-inset text-muted border border-line",
};

export function RoleBadge({ role }: { role: Role }) {
  return (
    <span className={`inline-flex shrink-0 rounded-md px-1.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide ${ROLE[role] ?? ROLE.guest}`}>
      {role}
    </span>
  );
}
