// c) "Modo estrés" — escalado del Auto Scaling Group.
//
// POST /api/stress sube la CPU de la instancia que responde. La política de
// target tracking (CPU promedio 50 %) hará que el ASG agregue instancias.

import { useEffect, useState } from "react";
import { startStress } from "../api";
import { castEffect } from "../effects";
import type { StressResponse } from "../types";
import { Panel } from "./Panel";

const MIN_SECONDS = 10;
const MAX_SECONDS = 300;

interface Attempt {
  id: number;
  response: StressResponse;
  endsAt: number;
}

export function StressMode() {
  const [seconds, setSeconds] = useState(180);
  const [attempts, setAttempts] = useState<Attempt[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());

  // Reloj para las cuentas regresivas.
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  const unleash = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await startStress(seconds);
      const duration = response.status === "accepted" ? response.seconds : response.remaining_seconds;
      setAttempts((previous) =>
        [{ id: Date.now(), response, endsAt: Date.now() + duration * 1000 }, ...previous].slice(0, 6),
      );
      castEffect(response.status === "accepted" ? "fuego" : "rayo", null, 2);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <Panel
      letter="C"
      title="Modo estrés"
      concept="Auto Scaling · Target tracking"
      lesson="en la consola de EC2 → Auto Scaling Groups → Activity verás el escalado hacia afuera. Cuando termina el estrés, el ASG vuelve al mínimo (más lento: el scale-in es conservador)."
    >
      <label className="slider">
        <span>
          Duración: <strong className="mono">{seconds} s</strong>
        </span>
        <input
          type="range"
          min={MIN_SECONDS}
          max={MAX_SECONDS}
          step={10}
          value={seconds}
          onChange={(event) => setSeconds(Number(event.target.value))}
        />
      </label>

      <button className="btn btn-fire btn-big" onClick={unleash} disabled={loading}>
        {loading ? "Invocando…" : "🔥 Desatar estrés"}
      </button>

      <div className="stress-steps">
        <strong>Qué va a pasar:</strong>
        <ol>
          <li>
            <strong>En segundos:</strong> en el panel A, “Carga de CPU”, la barra de la instancia sube al 100 %.
          </li>
          <li>
            <strong>Cuando el PROMEDIO pasa la marca del 50 %:</strong> CloudWatch dispara la alarma del ASG.
          </li>
          <li>
            <strong>En 5–10 min:</strong> aparece una instancia nueva en el panel A (y en ASG → Activity).
          </li>
        </ol>
      </div>

      <div className="warning">
        <strong>⏳ El ASG no reacciona al instante.</strong> CloudWatch publica la CPU cada minuto, la alarma necesita
        varios datos seguidos por encima del 50 % y la instancia nueva tiene que arrancar y pasar el health check.
        Cuenta con <strong>5 a 10 minutos</strong>.
        <br />
        <strong>Ojo:</strong> el objetivo es la CPU <em>promedio</em>. Con 2 instancias, estresar solo una (100 % + 0 %)
        da 50 % y puede no escalar. Presiona varias veces hasta que <em>todas</em> respondan “ya está estresada”.
      </div>

      {error && <p className="error-text">Falló la petición: {error}</p>}

      <ul className="stress-list">
        {attempts.map(({ id, response, endsAt }) => {
          const remaining = Math.max(0, Math.ceil((endsAt - now) / 1000));
          const accepted = response.status === "accepted";
          return (
            <li key={id} className={accepted ? "stress-ok" : "stress-busy"}>
              <span className="mono">{response.instance_id}</span>
              <span className="muted">{response.availability_zone}</span>
              <span>
                {accepted ? `quemando CPU ${response.seconds} s` : "ya está estresada"}
                {remaining > 0 ? ` · quedan ${remaining} s` : " · terminó"}
              </span>
            </li>
          );
        })}
      </ul>
    </Panel>
  );
}
