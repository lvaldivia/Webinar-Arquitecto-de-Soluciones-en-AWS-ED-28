// c) "Modo estrés" — escalado del Auto Scaling Group.
//
// POST /api/stress sube la CPU de la instancia que responde. La política de
// escalado por pasos (CPU promedio >60 % durante 10 segundos) agrega instancias.

import { useEffect, useState } from "react";
import { startStress, stopStressOnInstances } from "../api";
import { castEffect } from "../effects";
import type { StressResponse } from "../types";
import type { ScalingViewProps } from "../useScalingStatus";
import { Panel } from "./Panel";

const MIN_SECONDS = 10;
const MAX_SECONDS = 300;

interface Attempt {
  id: number;
  response: StressResponse;
  endsAt: number;
  stopped?: boolean;
}

export function StressMode({ scaling, scalingError }: ScalingViewProps) {
  const [seconds, setSeconds] = useState(300);
  const [attempts, setAttempts] = useState<Attempt[]>([]);
  const [loading, setLoading] = useState(false);
  const [stopping, setStopping] = useState(false);
  const [stopMessage, setStopMessage] = useState<string | null>(null);
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
    setStopMessage(null);
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

  const stop = async () => {
    setStopping(true);
    setError(null);
    setStopMessage(null);
    const ids = scaling?.status === "ok"
      ? scaling.instances.filter((item) => item.state === "ready").map((item) => item.instance_id)
      : attempts.filter((item) => item.endsAt > Date.now()).map((item) => item.response.instance_id);
    try {
      const result = await stopStressOnInstances(ids, (id) => {
        setAttempts((previous) => previous.map((item) => item.response.instance_id === id
          ? { ...item, endsAt: Date.now(), stopped: true } : item));
      });
      if (result.stopped.length > 0) {
        setStopMessage(`Estrés detenido en ${result.stopped.length} instancia(s). AWS reducirá capacidad cuando confirme CPU baja.`);
      }
      if (result.pending.length > 0 || result.stopped.length === 0) {
        setError("No se pudo confirmar la parada en todas las instancias. Pulsa Parar estrés otra vez.");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setStopping(false);
    }
  };

  return (
    <Panel
      letter="C"
      title="Modo estrés"
      concept="Auto Scaling · Escalado por pasos"
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

      <div className="stress-controls">
        <button className="btn btn-fire btn-big" onClick={unleash} disabled={loading || stopping}>
          {loading ? "Invocando…" : "🔥 Desatar estrés"}
        </button>
        <button className="btn btn-ghost" onClick={stop} disabled={loading || stopping}>
          {stopping ? "Deteniendo estrés…" : "⏹ Parar estrés"}
        </button>
      </div>
      <p className="muted">La carga termina sola al cumplirse el tiempo. También puedes detenerla antes con este botón.</p>
      {stopMessage && <p role="status">{stopMessage}</p>}

      <div className={`scaling-status ${scaling?.deploying ? "scaling-deploying" : ""}`} role="status" aria-live="polite">
        {scalingError ? (
          <strong>No se pudo consultar AWS. Reintentando…</strong>
        ) : scaling?.status === "disabled" ? (
          <strong>El estado del Auto Scaling está disponible en el despliegue de AWS.</strong>
        ) : scaling?.status === "ok" ? (
          <>
            <strong>
              {scaling.deploying > 0
                ? `🚀 Desplegando ${scaling.deploying === 1 ? "una nueva instancia" : `${scaling.deploying} nuevas instancias`}…`
                : scaling.instances.some((item) => item.state === "terminating")
                  ? "Retirando capacidad después del estrés…"
                  : scaling.ready > scaling.minimum
                    ? "✓ Capacidad ampliada: nuevas instancias listas para atender"
                    : "Observando la CPU · listo para escalar"}
            </strong>
            <p>{scaling.ready} listas · {scaling.deploying} arrancando · objetivo {scaling.desired} · máximo {scaling.maximum}</p>
            <ul>
              {scaling.instances.map((item) => (
                <li key={item.instance_id}>
                  <span className="mono">{item.instance_id}</span>
                  <span>{item.state === "ready" ? "✓ Lista para atender" : item.state === "deploying" ? "⏳ Arrancando y comprobando salud" : "Retirando"}</span>
                </li>
              ))}
            </ul>
          </>
        ) : <strong>Consultando el estado del grupo en AWS…</strong>}
      </div>

      <div className="stress-steps">
        <strong>Qué va a pasar:</strong>
        <ol>
          <li>
            <strong>En segundos:</strong> en el panel A, “Carga de CPU”, la barra de la instancia sube al 100 %.
          </li>
          <li>
            <strong>CPU promedio superior al 60 % durante unos 10 segundos:</strong> CloudWatch dispara la alarma del ASG.
          </li>
          <li>
            <strong>Aquí verás “Desplegando una nueva instancia”:</strong> tras arrancar y pasar el health check,
            la nueva instancia aparecerá en el panel A. El grupo puede crecer de 2 a 4 instancias.
          </li>
        </ol>
      </div>

      <div className="warning">
        <strong>⏳ El ASG no reacciona al instante.</strong> Con la configuración Terraform de la demo, la alarma necesita
        una muestra de 10 segundos por encima del 60 %. La imagen preparada evita instalar y compilar al arrancar.
        Buscamos ver capacidad nueva en alrededor de un minuto; el tiempo real depende del lanzamiento de EC2.
        <br />
        <strong>Para probar:</strong> deja 300 s y presiona varias veces para cargar ambas instancias.
        Con 2 instancias, una al 100 % y otra al 0 % dan un promedio del 50 %: debes cargar ambas para superar el 60 %.
        Para seguir creciendo, mantén la carga mientras las nuevas instancias terminan de arrancar.
      </div>

      {error && <p className="error-text">Falló la petición: {error}</p>}

      <ul className="stress-list">
        {attempts.map(({ id, response, endsAt, stopped }) => {
          const remaining = Math.max(0, Math.ceil((endsAt - now) / 1000));
          const accepted = response.status === "accepted";
          return (
            <li key={id} className={accepted ? "stress-ok" : "stress-busy"}>
              <span className="mono">{response.instance_id}</span>
              <span className="muted">{response.availability_zone}</span>
              <span>
                {stopped ? "estrés detenido" : accepted ? `quemando CPU ${response.seconds} s` : "ya está estresada"}
                {!stopped && (remaining > 0 ? ` · quedan ${remaining} s` : " · terminó")}
              </span>
            </li>
          );
        })}
      </ul>
    </Panel>
  );
}
