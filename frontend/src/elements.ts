// Cada zona de disponibilidad (AZ) se representa con un elemento mágico.
// us-east-1a -> fuego, us-east-1b -> viento, us-east-1c -> agua, etc.
// Así, en la proyección se ve de un vistazo desde qué AZ respondió el ALB.

import type { ElementName } from "./types";

export interface MagicElement {
  name: ElementName;
  label: string;
  color: string;
  glow: string;
}

export const ELEMENTS: Record<ElementName, MagicElement> = {
  fuego: { name: "fuego", label: "Fuego", color: "#ff7a3d", glow: "rgba(255, 122, 61, 0.45)" },
  viento: { name: "viento", label: "Viento", color: "#3ddc97", glow: "rgba(61, 220, 151, 0.45)" },
  agua: { name: "agua", label: "Agua", color: "#4fc3f7", glow: "rgba(79, 195, 247, 0.45)" },
  tierra: { name: "tierra", label: "Tierra", color: "#c9955c", glow: "rgba(201, 149, 92, 0.45)" },
  rayo: { name: "rayo", label: "Rayo", color: "#ffd84d", glow: "rgba(255, 216, 77, 0.45)" },
  luz: { name: "luz", label: "Luz", color: "#f3ecd6", glow: "rgba(243, 236, 214, 0.45)" },
};

const AZ_ORDER: ElementName[] = ["fuego", "viento", "agua", "tierra", "rayo", "luz"];

function hash(text: string): number {
  let value = 0;
  for (const char of text) value = (value * 31 + char.charCodeAt(0)) >>> 0;
  return value;
}

export function isLocalAz(az: string): boolean {
  return az.startsWith("local");
}

/**
 * Elemento según la AZ (por la letra final: a, b, c...).
 * En local todas las réplicas dicen "local-az", así que usamos el
 * instance_id para que cada réplica tenga igual un color distinto.
 */
export function elementFor(az: string, instanceId = ""): MagicElement {
  if (isLocalAz(az)) {
    return ELEMENTS[AZ_ORDER[hash(instanceId) % AZ_ORDER.length]];
  }
  const letter = az.at(-1) ?? "a";
  const index = Math.max(0, letter.charCodeAt(0) - "a".charCodeAt(0));
  return ELEMENTS[AZ_ORDER[index % AZ_ORDER.length]];
}
