// Cliente de la API.
//
// IMPORTANTE: todas las rutas son relativas (/api/...). En AWS el navegador
// le pide todo a CloudFront (mismo dominio) y CloudFront enruta /api/* al ALB.
// Al ser el mismo origen, no hace falta configurar CORS.

import type { InstanceInfo, ScalingStatus, Spell, StressResponse, StressStopResponse } from "./types";

const TIMEOUT_MS = 4000;

interface RawResponse {
  status: number;
  ok: boolean;
  headers: Headers;
  data: unknown;
}

async function request(path: string, init: RequestInit = {}): Promise<RawResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const response = await fetch(path, {
      ...init,
      // no-store: el navegador no usa su propia caché; la petición siempre sale.
      cache: "no-store",
      signal: controller.signal,
      headers: { Accept: "application/json", ...(init.body ? { "Content-Type": "application/json" } : {}) },
    });

    // Un 502/504 del ALB o de CloudFront llega como HTML, no como JSON.
    const text = await response.text();
    let data: unknown = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = null;
    }
    return { status: response.status, ok: response.ok, headers: response.headers, data };
  } catch (error) {
    if (controller.signal.aborted) {
      throw new Error(`Sin respuesta en ${TIMEOUT_MS / 1000} s`);
    }
    throw new Error("Error de red", { cause: error });
  } finally {
    clearTimeout(timer);
  }
}

function fail(response: RawResponse): never {
  throw new Error(`HTTP ${response.status}`);
}

export async function getInfo(): Promise<InstanceInfo> {
  const response = await request("/api/info");
  if (!response.ok) fail(response);
  return response.data as InstanceInfo;
}

export async function getScalingStatus(): Promise<ScalingStatus> {
  const response = await request("/api/scaling");
  if (!response.ok) fail(response);
  return response.data as ScalingStatus;
}

export async function castSpell(): Promise<Spell> {
  const response = await request("/api/spell", { method: "POST" });
  if (!response.ok) fail(response);
  return response.data as Spell;
}

export async function startStress(seconds: number): Promise<StressResponse> {
  const response = await request("/api/stress", {
    method: "POST",
    body: JSON.stringify({ seconds }),
  });
  // 202 = aceptado, 409 = esa instancia ya está estresada. Ambos son respuestas válidas.
  if (response.status !== 202 && response.status !== 409) fail(response);
  return response.data as StressResponse;
}

export async function stopStress(): Promise<StressStopResponse> {
  const response = await request("/api/stress/stop", { method: "POST" });
  if (response.status !== 200 && response.status !== 202) fail(response);
  return response.data as StressStopResponse;
}

/** Cada respuesta confirma una EC2; no confundimos parar una con parar el grupo. */
export async function stopStressOnInstances(ids: string[], onStopped: (id: string) => void) {
  const targets = new Set(ids);
  const stopped = new Set<string>();
  for (let round = 0; round < 6; round++) {
    const batch = await Promise.allSettled(Array.from({ length: 4 }, () => stopStress()));
    for (const result of batch) {
      if (result.status === "fulfilled" && result.value.status === "stopped") {
        if (!stopped.has(result.value.instance_id)) {
          stopped.add(result.value.instance_id);
          onStopped(result.value.instance_id);
        }
      }
    }
    if (stopped.size > 0 && [...targets].every((id) => stopped.has(id))) break;
  }
  let pending = [...targets].filter((id) => !stopped.has(id));
  if (pending.length > 0) {
    try {
      const current = await getScalingStatus();
      if (current.status === "ok") {
        const ready = new Set(current.instances.filter((item) => item.state === "ready").map((item) => item.instance_id));
        pending = pending.filter((id) => ready.has(id));
      }
    } catch { /* Conservamos los pendientes si no podemos confirmar su retirada. */ }
  }
  return { stopped: [...stopped], pending };
}

export interface CacheProbe {
  status: number;
  xCache: string | null;
  age: string | null;
  body: unknown;
}

/** Pide un recurso y devuelve los encabezados de caché que agrega CloudFront. */
export async function probeCache(path: string): Promise<CacheProbe> {
  const response = await request(path);
  return {
    status: response.status,
    xCache: response.headers.get("x-cache"),
    age: response.headers.get("age"),
    body: response.data,
  };
}
