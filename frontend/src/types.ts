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
