// Mini "bus de eventos" para pedir animaciones de hechizos.
// Cualquier panel llama a castEffect(...) y el ParticleCanvas lo dibuja.

import type { ElementName } from "./types";

export interface SpellEffect {
  element: ElementName;
  x: number;
  y: number;
  intensity: number;
}

type Listener = (effect: SpellEffect) => void;

const listeners = new Set<Listener>();

export function onSpellEffect(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** Lanza un hechizo desde el centro de `origin` (o del centro de la pantalla). */
export function castEffect(element: ElementName, origin?: HTMLElement | null, intensity = 1): void {
  const rect = origin?.getBoundingClientRect();
  const x = rect ? rect.left + rect.width / 2 : window.innerWidth / 2;
  const y = rect ? rect.top + rect.height / 2 : window.innerHeight / 2;
  listeners.forEach((listener) => listener({ element, x, y, intensity }));
}
