import type { ScalingStatus } from "./types";

export const STALE_AFTER_MS = 20_000;

/** AWS confirma quién atiende; en local/sin conexión solo hay observaciones recientes. */
export function isServing(id: string, seenAt: number, now: number, scaling: ScalingStatus | null): boolean {
  if (scaling?.status === "ok") {
    return scaling.instances.some((item) => item.instance_id === id && item.state === "ready");
  }
  return now - seenAt < STALE_AFTER_MS;
}
