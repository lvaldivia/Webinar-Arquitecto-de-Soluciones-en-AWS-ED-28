// Arte original hecho con SVG: trébol de cuatro hojas, círculo mágico e
// íconos de elementos. No usa imágenes ni recursos de terceros.

import type { CSSProperties } from "react";
import type { ElementName } from "../types";

// Hoja en forma de corazón con la punta en el origen (0, 0).
const LEAF_PATH = "M0 0C-2-6-12-10-12-20C-12-28-2-30 0-22C2-30 12-28 12-20C12-10 2-6 0 0Z";

export function CloverEmblem({ size = 88 }: { size?: number }) {
  return (
    <svg className="clover-emblem" width={size} height={size} viewBox="0 0 100 100" aria-hidden="true">
      <defs>
        <radialGradient id="leaf-fill" cx="50%" cy="80%" r="80%">
          <stop offset="0%" stopColor="#7be3a8" />
          <stop offset="100%" stopColor="#1f6b43" />
        </radialGradient>
      </defs>
      <circle cx="50" cy="50" r="46" fill="none" stroke="#d4af37" strokeWidth="1.5" strokeDasharray="3 5" className="spin-slow" />
      <path d="M50 52 Q58 75 66 92" fill="none" stroke="#3fa66b" strokeWidth="3" strokeLinecap="round" />
      <g transform="translate(50 50)" fill="url(#leaf-fill)" stroke="#d4af37" strokeWidth="1.2">
        {[45, 135, 225, 315].map((angle) => (
          <path key={angle} d={LEAF_PATH} transform={`rotate(${angle}) scale(1.35)`} />
        ))}
      </g>
      <circle cx="50" cy="50" r="3" fill="#d4af37" />
    </svg>
  );
}

/** Círculo mágico giratorio que se dibuja detrás de las cartas. */
export function MagicCircle({ color, className = "" }: { color: string; className?: string }) {
  const hexagram = (offset: number) =>
    [0, 1, 2]
      .map((i) => {
        const angle = ((i * 120 + offset - 90) * Math.PI) / 180;
        return `${100 + Math.cos(angle) * 70},${100 + Math.sin(angle) * 70}`;
      })
      .join(" ");

  return (
    <svg className={`magic-circle ${className}`} viewBox="0 0 200 200" style={{ color } as CSSProperties} aria-hidden="true">
      <g fill="none" stroke="currentColor">
        <circle cx="100" cy="100" r="95" strokeWidth="1.5" />
        <circle cx="100" cy="100" r="86" strokeWidth="5" strokeDasharray="2 9" className="spin-slow" />
        <g className="spin-reverse">
          <polygon points={hexagram(0)} strokeWidth="1.5" />
          <polygon points={hexagram(60)} strokeWidth="1.5" />
        </g>
        <circle cx="100" cy="100" r="40" strokeWidth="1" />
      </g>
    </svg>
  );
}

const ICON_PATHS: Record<ElementName, { d: string; stroke?: boolean }> = {
  fuego: { d: "M12 2c1 4 5 6 5 11a5 5 0 0 1-10 0c0-3 2-4 2-7 2 1 3 3 3 5 1-2 1-5 0-9z" },
  viento: { d: "M3 8h10a3 3 0 1 0-3-3M3 12h15a3 3 0 1 1-3 3M3 16h7", stroke: true },
  agua: { d: "M12 2C9 7 6 10 6 14a6 6 0 0 0 12 0c0-4-3-7-6-12z" },
  tierra: { d: "M2 20l7-12 4 6 3-4 6 10z" },
  rayo: { d: "M13 2L4 14h7l-1 8 9-12h-7z" },
  luz: { d: "M12 2l2.5 7.5H22l-6 4.5 2.5 7.5L12 17l-6.5 4.5L8 14 2 9.5h7.5z" },
};

export function ElementIcon({ element, color, size = 24 }: { element: ElementName; color: string; size?: number }) {
  const icon = ICON_PATHS[element];
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path
        d={icon.d}
        fill={icon.stroke ? "none" : color}
        stroke={color}
        strokeWidth={icon.stroke ? 2 : 1}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
