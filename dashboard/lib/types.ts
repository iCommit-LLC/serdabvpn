// Shapes from serdabvpn/docs/api.md (the serdabd admin API).

export type Role = "owner" | "family" | "kid" | "guest";

export type Status =
  | "disabled"
  | "expired"
  | "paused"
  | "over_quota"
  | "pending"
  | "online"
  | "idle";

export interface Usage {
  todayDown: number;
  todayUp: number;
  monthDown: number;
  monthUp: number;
}

export interface Device {
  name: string;
  role: Role;
  address: string;
  status: Status;
  enabled: boolean;
  canShare: boolean;
  filtered: boolean;
  logged: boolean;
  speedMbps: number | null;
  quotaGb: number | null;
  createdAt: number;
  createdBy: string;
  expiresAt: number | null;
  firstHandshakeAt: number | null;
  lastHandshakeAt: number | null;
  usage: Usage;
}

export interface Overview {
  ownerName: string;
  paused: boolean;
  endpoint: string;
  costPerGb: number;
  devices: { total: number; online: number };
  today: { down: number; up: number };
  month: { down: number; up: number; estCostUsd: number };
}

export interface DailyUsage {
  day: string; // YYYY-MM-DD
  down: number;
  up: number;
}

export interface Session {
  start: number;
  end: number | null;
  down: number;
  up: number;
}

export interface DeviceDetail {
  device: Device;
  daily: DailyUsage[];
  sessions: Session[];
  invited: string[];
}

export interface DomainRow {
  ts: number;
  domain: string;
  blocked: boolean;
  count: number;
}

export interface BlockedRow {
  ts: number;
  device: string;
  domain: string;
  count: number;
}

export type DevicePatch = Partial<{
  enabled: boolean;
  role: Role;
  canShare: boolean;
  filtered: boolean;
  logged: boolean;
  speedMbps: number | null;
  quotaGb: number | null;
  expiresAt: number | null;
}>;

export const ROLES: Role[] = ["owner", "family", "kid", "guest"];
export const NAME_RE = /^[a-z0-9][a-z0-9-]{0,31}$/;
