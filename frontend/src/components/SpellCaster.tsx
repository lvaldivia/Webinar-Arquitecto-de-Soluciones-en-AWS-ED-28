// b) "Lanzar hechizo" — una llamada POST a la API detrás del ALB.
// La carta muestra qué instancia generó el hechizo: cada clic puede caer en otra.

import { useRef, useState } from "react";
import { castSpell } from "../api";
import { castEffect } from "../effects";
import { ELEMENTS } from "../elements";
import type { Spell } from "../types";
import { ElementIcon, MagicCircle } from "./Art";
import { Panel } from "./Panel";

function rarity(power: number): string {
  if (power >= 90) return "Legendario";
  if (power >= 70) return "Épico";
  if (power >= 40) return "Raro";
  return "Común";
}

export function SpellCaster() {
  const [spell, setSpell] = useState<Spell | null>(null);
  const [castCount, setCastCount] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const cardRef = useRef<HTMLDivElement>(null);

  const cast = async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await castSpell();
      setSpell(result);
      setCastCount((value) => value + 1);
      // Esperamos un frame para que la carta nueva exista antes de animar.
      requestAnimationFrame(() => castEffect(result.element, cardRef.current, 1.6));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  };

  const element = spell ? ELEMENTS[spell.element] : null;

  return (
    <Panel
      letter="B"
      title="Lanzar hechizo"
      concept="API detrás del ALB"
      lesson="el hechizo lo genera el backend (POST /api/spell). Lanza varios y mira el campo “lanzado por”: cambia de instancia según el reparto del ALB."
    >
      <button className="btn btn-gold btn-big" onClick={cast} disabled={loading}>
        {loading ? "Conjurando…" : "✦ Lanzar hechizo"}
      </button>

      {error && <p className="error-text">No se pudo lanzar: {error}</p>}

      {spell && element && (
        <div
          key={castCount}
          ref={cardRef}
          className="spell-card cast-in"
          style={{ borderColor: element.color, boxShadow: `0 0 36px ${element.glow}` }}
        >
          <MagicCircle color={element.color} className="card-circle" />
          <div className="spell-element" style={{ color: element.color }}>
            <ElementIcon element={element.name} color={element.color} size={30} />
            {element.label} · {rarity(spell.power)}
          </div>
          <h3 className="spell-name">{spell.name}</h3>
          <div className="power">
            <span>Poder</span>
            <div className="bar">
              <div className="bar-fill" style={{ width: `${spell.power}%`, background: element.color }} />
            </div>
            <span className="mono">{spell.power}</span>
          </div>
          <p className="caster">
            Lanzado por <span className="mono">{spell.caster.instance_id}</span> ·{" "}
            <span className="mono">{spell.caster.availability_zone}</span>
          </p>
        </div>
      )}
    </Panel>
  );
}
