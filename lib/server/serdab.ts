import "server-only";
import { redirect } from "next/navigation";
import { getAdminKey } from "./session";
import type {
  BlockedRow,
  Device,
  DeviceDetail,
  DevicePatch,
  DomainRow,
  Overview,
  Role,
} from "@/lib/types";

/**
 * Server-side client for serdabd's admin API (serdabvpn/docs/api.md).
 *
 * SERDAB_API is the VM's private address on the GCP network; Cloud Run reaches
 * it through direct VPC egress. Locally it is the mock (`npm run mock`).
 */
const SERDAB_API = (process.env.SERDAB_API ?? "http://127.0.0.1:8801").replace(/\/$/, "");
const TIMEOUT_MS = 8000;

export class SerdabError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly path: string,
  ) {
    super(message);
  }
}

async function call(path: string, init: RequestInit = {}, key?: string | null): Promise<Response> {
  const headers = new Headers(init.headers);
  const k = key ?? (await getAdminKey());
  if (k) headers.set("authorization", `Bearer ${k}`);
  if (init.body && !headers.has("content-type")) headers.set("content-type", "application/json");
  try {
    return await fetch(`${SERDAB_API}${path}`, {
      ...init,
      headers,
      cache: "no-store",
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (e) {
    throw new SerdabError(0, `The server did not answer (${(e as Error).message}).`, path);
  }
}

async function json<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await call(path, init);
  // A key that stopped working (rotated on the server): drop the cookie.
  if (res.status === 401) redirect("/logout");
  if (!res.ok) {
    let message = `serdabd ${res.status}`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) message = body.error;
    } catch {
      /* not JSON */
    }
    throw new SerdabError(res.status, message, path);
  }
  return (await res.json()) as T;
}

const enc = encodeURIComponent;

/** Login check: true if serdabd accepts this key. Throws SerdabError(0) if unreachable. */
export async function validateKey(key: string): Promise<boolean> {
  const res = await call("/admin/v1/overview", {}, key);
  return res.ok;
}

export function getOverview(): Promise<Overview> {
  return json<Overview>("/admin/v1/overview");
}

export async function listDevices(): Promise<Device[]> {
  return (await json<{ devices: Device[] }>("/admin/v1/devices")).devices;
}

export function getDevice(name: string): Promise<DeviceDetail> {
  return json<DeviceDetail>(`/admin/v1/devices/${enc(name)}`);
}

export interface DomainQuery {
  limit?: number;
  before?: number;
  q?: string;
  blocked?: boolean;
}

export function getDomains(
  name: string,
  query: DomainQuery = {},
): Promise<{ logged: boolean; domains: DomainRow[] }> {
  const p = new URLSearchParams();
  p.set("limit", String(query.limit ?? 200));
  if (query.before) p.set("before", String(query.before));
  if (query.q) p.set("q", query.q);
  if (query.blocked) p.set("blocked", "1");
  return json(`/admin/v1/devices/${enc(name)}/domains?${p}`);
}

export async function getBlocked(limit = 100): Promise<BlockedRow[]> {
  return (await json<{ blocked: BlockedRow[] }>(`/admin/v1/blocked?limit=${limit}`)).blocked;
}

export function createDevice(name: string, role: Role): Promise<{ device: Device; link: string }> {
  return json("/admin/v1/devices", { method: "POST", body: JSON.stringify({ name, role }) });
}

export async function patchDevice(name: string, patch: DevicePatch): Promise<Device> {
  return (
    await json<{ device: Device }>(`/admin/v1/devices/${enc(name)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    })
  ).device;
}

export async function revokeDevice(name: string): Promise<string[]> {
  return (await json<{ revoked: string[] }>(`/admin/v1/devices/${enc(name)}`, { method: "DELETE" }))
    .revoked;
}

/** The invitation link. It holds the device's private key: render, never log. */
export async function getLink(name: string): Promise<string> {
  return (await json<{ link: string }>(`/admin/v1/devices/${enc(name)}/link`)).link;
}

export async function setPaused(paused: boolean): Promise<boolean> {
  return (
    await json<{ paused: boolean }>("/admin/v1/pause", {
      method: "POST",
      body: JSON.stringify({ paused }),
    })
  ).paused;
}
