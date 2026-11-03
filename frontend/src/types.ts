// Tipos de las respuestas de la API (ver backend/app/main.py).

export type ElementName = "fuego" | "viento" | "agua" | "tierra" | "rayo" | "luz";

export interface Caster {
  instance_id: string;
  availability_zone: string;
}

export interface InstanceInfo extends Caster {
  region: string;
  hostname: string;
  version: string;
  timestamp: string;
  /** % de CPU de la instancia (null si no se puede medir). */
  cpu_percent: number | null;
  /** Segundos que le quedan al "modo estrés" en esta instancia (0 = sin estrés). */
  stress_remaining_seconds: number;
}

export interface Spell {
  name: string;
  element: ElementName;
  power: number;
  caster: Caster;
  timestamp: string;
}

export interface StressAccepted extends Caster {
  status: "accepted";
  seconds: number;
  max_seconds: number;
}

export interface StressBusy extends Caster {
  status: "busy";
  message: string;
  remaining_seconds: number;
}

export type StressResponse = StressAccepted | StressBusy;

export interface StressStopResponse extends Caster {
  status: "stopped" | "stopping";
  remaining_seconds: number;
}

export interface ScalingStatus {
  status: "ok" | "disabled";
  desired: number;
  minimum: number;
  maximum: number;
  ready: number;
  deploying: number;
  instances: Array<Caster & { state: "ready" | "deploying" | "terminating" }>;
}
