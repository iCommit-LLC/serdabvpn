"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import {
  SerdabError,
  createDevice,
  patchDevice,
  revokeDevice,
  setPaused,
} from "@/lib/server/serdab";
import { endOfDay } from "@/lib/format";
import { NAME_RE, ROLES, type DevicePatch, type Role } from "@/lib/types";

/** Run a serdabd write; on a serdabd error come back to `back` with the message. */
async function attempt<T>(back: string, fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof SerdabError) {
      const sep = back.includes("?") ? "&" : "?";
      redirect(`${back}${sep}error=${encodeURIComponent(e.message)}`);
    }
    throw e;
  }
}

const devicePath = (name: string) => `/devices/${encodeURIComponent(name)}`;

export async function pauseAll(formData: FormData) {
  const paused = formData.get("paused") === "1";
  await attempt("/", () => setPaused(paused));
  revalidatePath("/");
  redirect(`/?done=${paused ? "paused" : "resumed"}`);
}

export async function setEnabled(formData: FormData) {
  const name = String(formData.get("name"));
  const enabled = formData.get("enabled") === "1";
  await attempt(devicePath(name), () => patchDevice(name, { enabled }));
  redirect(`${devicePath(name)}?done=${enabled ? "enabled" : "disabled"}`);
}

function limit(raw: FormDataEntryValue | null): number | null | "bad" {
  const s = String(raw ?? "").trim();
  if (s === "") return null;
  const n = Number(s);
  return Number.isInteger(n) && n > 0 && n <= 100000 ? n : "bad";
}

export async function saveSettings(formData: FormData) {
  const name = String(formData.get("name"));
  const back = devicePath(name);
  const role = String(formData.get("role")) as Role;
  if (!ROLES.includes(role)) redirect(`${back}?error=${encodeURIComponent("Unknown role.")}`);

  const quotaGb = limit(formData.get("quotaGb"));
  const speedMbps = limit(formData.get("speedMbps"));
  if (quotaGb === "bad" || speedMbps === "bad") {
    redirect(`${back}?error=${encodeURIComponent("Limits are whole numbers above zero, or empty for none.")}`);
  }

  const patch: DevicePatch = {
    role,
    canShare: formData.get("canShare") === "on",
    filtered: formData.get("filtered") === "on",
    logged: formData.get("logged") === "on",
    quotaGb,
    speedMbps,
  };
  if (formData.has("expiresAt")) {
    const raw = String(formData.get("expiresAt") ?? "");
    patch.expiresAt = raw === "" ? null : endOfDay(raw);
  }

  const wasLogged = formData.get("wasLogged") === "1";
  await attempt(back, () => patchDevice(name, patch));
  redirect(`${back}?done=${!wasLogged && patch.logged ? "logged-on" : "saved"}`);
}

export async function revoke(formData: FormData) {
  const name = String(formData.get("name"));
  const revoked = await attempt(devicePath(name), () => revokeDevice(name));
  revalidatePath("/");
  redirect(`/?done=revoked&names=${encodeURIComponent(revoked.join(","))}`);
}

export async function invite(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim().toLowerCase();
  const role = String(formData.get("role")) as Role;
  const back = `/invite?name=${encodeURIComponent(name)}&role=${encodeURIComponent(role)}`;
  if (!NAME_RE.test(name)) {
    redirect(`${back}&error=${encodeURIComponent("A name is lowercase letters, digits and dashes, up to 32.")}`);
  }
  if (!["family", "kid", "guest"].includes(role)) {
    redirect(`${back}&error=${encodeURIComponent("Pick family, kid or guest.")}`);
  }
  await attempt(back, () => createDevice(name, role));
  revalidatePath("/");
  redirect(`${devicePath(name)}?invite=1&done=created`);
}
