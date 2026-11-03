// d) "Espejo del caché" — caché de CloudFront.
//
// CloudFront agrega el encabezado X-Cache a cada respuesta:
//   "Miss from cloudfront"  -> tuvo que ir al origen (S3 o el ALB)
//   "Hit from cloudfront"   -> lo sirvió desde la caché del edge
// Comparamos un archivo estático (cacheado) con la API (caching deshabilitado).

import { useState } from "react";
import { probeCache } from "../api";
import { castEffect } from "../effects";
import { Panel } from "./Panel";

const TARGETS = {
  static: { label: "Estático", path: "/assets/grimorio.json" },
  api: { label: "API", path: "/api/health" },
} as const;

type Target = keyof typeof TARGETS;
type Verdict = "hit" | "miss" | "local" | "error";

interface Reflection {
  id: number;
  target: Target;
  status: number;
  xCache: string | null;
  age: string | null;
  verdict: Verdict;
  at: Date;
}

function classify(status: number, xCache: string | null): Verdict {
  if (status >= 400 || status === 0) return "error";
  if (!xCache) return "local";
  return /hit/i.test(xCache) ? "hit" : "miss";
}

const VERDICT_TEXT: Record<Verdict, string> = {
  hit: "Hit — servido desde el edge",
  miss: "Miss — CloudFront fue al origen",
  local: "sin CloudFront (local)",
  error: "Error",
};

export function CacheMirror() {
  const [reflections, setReflections] = useState<Reflection[]>([]);
  const [grimoire, setGrimoire] = useState<{ name?: string; message?: string } | null>(null);
  const [loading, setLoading] = useState(false);

  const look = async (target: Target) => {
    setLoading(true);
    let reflection: Reflection;
    try {
      const probe = await probeCache(TARGETS[target].path);
      reflection = {
        id: Date.now(), target, status: probe.status, xCache: probe.xCache, age: probe.age,
        verdict: classify(probe.status, probe.xCache), at: new Date(),
      };
      if (target === "static" && probe.body && typeof probe.body === "object") {
        setGrimoire(probe.body as { name?: string; message?: string });
      }
    } catch (error) {
      reflection = {
        id: Date.now(), target, status: 0, xCache: error instanceof Error ? error.message : null, age: null,
        verdict: "error", at: new Date(),
      };
    }
    setReflections((previous) => [reflection, ...previous].slice(0, 8));
    castEffect(reflection.verdict === "hit" ? "luz" : "agua", null, 0.8);
    setLoading(false);
  };

  const latest = reflections[0];

  return (
    <Panel
      letter="D"
      title="Espejo del caché"
      concept="CloudFront · Caché en el edge"
      lesson={
        <>
          la primera vez el estático dice <em>Miss</em> y la segunda <em>Hit</em>: CloudFront lo guardó. La API siempre
          dice <em>Miss</em> porque /api/* tiene el caché deshabilitado. Tras desplegar e invalidar, vuelve a ser Miss.
        </>
      }
    >
      <div className="mirror-buttons">
        <button className="btn btn-gold" onClick={() => look("static")} disabled={loading}>
          🪞 Mirar estático
        </button>
        <button className="btn" onClick={() => look("api")} disabled={loading}>
          Mirar /api
        </button>
      </div>

      <div className={`mirror verdict-${latest?.verdict ?? "none"}`}>
        {latest ? (
          <>
            <span className="mirror-path mono">{TARGETS[latest.target].path}</span>
            <span className="mirror-verdict">{VERDICT_TEXT[latest.verdict]}</span>
            <span className="mono muted">
              X-Cache: {latest.xCache ?? "(no existe)"}
              {latest.age ? ` · Age: ${latest.age} s` : ""}
            </span>
          </>
        ) : (
          <span className="muted">El espejo aún no refleja nada.</span>
        )}
      </div>

      {grimoire?.name && (
        <blockquote className="grimoire-quote">
          <strong>{grimoire.name}</strong>
          <span>{grimoire.message}</span>
        </blockquote>
      )}

      <ul className="mirror-history">
        {reflections.map((item) => (
          <li key={item.id} className={`verdict-${item.verdict}`}>
            <span className="mono">{item.at.toLocaleTimeString("es", { hour12: false })}</span>
            <span>{TARGETS[item.target].label}</span>
            <span className="mono">{item.xCache ?? "sin CloudFront (local)"}</span>
          </li>
        ))}
      </ul>
    </Panel>
  );
}
