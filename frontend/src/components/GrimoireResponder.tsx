// a) "¿Qué grimorio respondió?" — reparto de tráfico del ALB.
//
// Cada 2 segundos llama a GET /api/info. El ALB elige una instancia sana del
// target group; la respuesta dice cuál fue (instance_id) y en qué AZ está.
// Si una instancia cae, veremos errores en rojo hasta que el ALB la marque
// unhealthy y deje de enviarle tráfico.

import { useCallback, useEffect, useRef, useState } from "react";
import { getInfo } from "../api";
import { castEffect } from "../effects";
import { elementFor, isLocalAz } from "../elements";
import type { InstanceInfo } from "../types";
import { ElementIcon, MagicCircle } from "./Art";
import { Panel } from "./Panel";

const POLL_INTERVAL_MS = 2000;
const HISTORY_SIZE = 20;
const ASG_CPU_TARGET = 50; // objetivo de la política de target tracking
const STALE_AFTER_MS = 20_000; // una instancia que no responde hace 20 s ya no cuenta

interface LogEntry {
  id: number;
  receivedAt: Date;
  latencyMs: number;
  info?: InstanceInfo;
  error?: string;
}

interface Counter {
  count: number;
  color: string;
  detail: string;
}

/** Último reporte de CPU de cada instancia. */
interface CpuReport {
  az: string;
  cpu: number | null;
  stressRemaining: number;
  seenAt: number;
}

const formatTime = (date: Date) => date.toLocaleTimeString("es", { hour12: false });

function cpuColor(cpu: number): string {
  if (cpu >= 80) return "#ff4e2a";
  if (cpu >= ASG_CPU_TARGET) return "#ffb347";
  return "#3ddc97";
}

/**
 * "Carga de CPU": muestra en segundos el efecto del modo estrés y el promedio
 * que mira el Auto Scaling Group (con una marca en el objetivo del 50 %).
 */
function CpuGauges({ reports }: { reports: Record<string, CpuReport> }) {
  const now = Date.now();
  const active = Object.entries(reports)
    .filter(([, report]) => now - report.seenAt < STALE_AFTER_MS && report.cpu !== null)
    .sort(([a], [b]) => a.localeCompare(b));

  const average = active.length
    ? Math.round(active.reduce((sum, [, report]) => sum + (report.cpu ?? 0), 0) / active.length)
    : null;
  const overTarget = average !== null && average > ASG_CPU_TARGET;

  return (
    <div className="cpu-block">
      <h3>Carga de CPU · lo que mira el Auto Scaling</h3>
      {active.length === 0 && <p className="muted">Sin datos de CPU todavía.</p>}

      {active.map(([instanceId, report]) => (
        <div key={instanceId} className="cpu-row">
          <span className="mono cpu-name">{instanceId}</span>
          <span className="muted">{report.az}</span>
          <div className="bar cpu-bar">
            <div className="bar-fill" style={{ width: `${report.cpu}%`, background: cpuColor(report.cpu ?? 0) }} />
            <div className="target-marker" style={{ left: `${ASG_CPU_TARGET}%` }} />
          </div>
          <span className="mono cpu-value">{Math.round(report.cpu ?? 0)} %</span>
          <span className="cpu-stress">{report.stressRemaining > 0 ? `🔥 estrés ${report.stressRemaining} s` : ""}</span>
        </div>
      ))}

      {average !== null && (
        <div className={`cpu-row cpu-average ${overTarget ? "over-target" : ""}`}>
          <span className="cpu-name">PROMEDIO</span>
          <span className="muted">{active.length} inst.</span>
          <div className="bar cpu-bar">
            <div className="bar-fill" style={{ width: `${average}%`, background: cpuColor(average) }} />
            <div className="target-marker" style={{ left: `${ASG_CPU_TARGET}%` }} />
          </div>
          <span className="mono cpu-value">{average} %</span>
          <span className="cpu-stress">
            {overTarget ? "▲ supera el 50 %: el ASG va a escalar" : `objetivo del ASG: ${ASG_CPU_TARGET} %`}
          </span>
        </div>
      )}
    </div>
  );
}

function TallyBars({ title, items }: { title: string; items: Array<[string, Counter]> }) {
  const total = items.reduce((sum, [, item]) => sum + item.count, 0);
  return (
    <div className="tally">
      <h3>{title}</h3>
      {items.length === 0 && <p className="muted">Aún no hay respuestas.</p>}
      {items.map(([label, item]) => {
        const percent = total ? Math.round((item.count / total) * 100) : 0;
        return (
          <div key={label} className="tally-row">
            <div className="tally-label">
              <span className="mono">{label}</span>
              <span className="muted">{item.detail}</span>
              <span className="tally-count">
                {item.count} · {percent}%
              </span>
            </div>
            <div className="bar">
              <div className="bar-fill" style={{ width: `${percent}%`, background: item.color }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

export function GrimoireResponder() {
  const [paused, setPaused] = useState(false);
  const [log, setLog] = useState<LogEntry[]>([]);
  const [current, setCurrent] = useState<LogEntry | null>(null);
  const [byInstance, setByInstance] = useState<Record<string, Counter>>({});
  const [byAz, setByAz] = useState<Record<string, Counter>>({});
  const [cpuReports, setCpuReports] = useState<Record<string, CpuReport>>({});
  const [failures, setFailures] = useState(0);

  const inFlight = useRef(false);
  const nextId = useRef(1);
  const cardRef = useRef<HTMLDivElement>(null);

  const poll = useCallback(async () => {
    if (inFlight.current) return; // no encimamos peticiones si una tarda
    inFlight.current = true;
    const startedAt = performance.now();
    const entry: LogEntry = { id: nextId.current++, receivedAt: new Date(), latencyMs: 0 };

    try {
      entry.info = await getInfo();
    } catch (error) {
      entry.error = error instanceof Error ? error.message : String(error);
    } finally {
      entry.latencyMs = Math.round(performance.now() - startedAt);
      entry.receivedAt = new Date();
      inFlight.current = false;
    }

    setLog((previous) => [entry, ...previous].slice(0, HISTORY_SIZE));

    if (!entry.info) {
      setFailures((value) => value + 1);
      return;
    }

    const { instance_id, availability_zone } = entry.info;
    const element = elementFor(availability_zone, instance_id);
    setCurrent(entry);
    setByInstance((previous) => ({
      ...previous,
      [instance_id]: { count: (previous[instance_id]?.count ?? 0) + 1, color: element.color, detail: availability_zone },
    }));
    setByAz((previous) => ({
      ...previous,
      [availability_zone]: {
        count: (previous[availability_zone]?.count ?? 0) + 1,
        color: isLocalAz(availability_zone) ? "#d4af37" : element.color,
        detail: isLocalAz(availability_zone) ? "local" : element.label,
      },
    }));
    setCpuReports((previous) => ({
      ...previous,
      [instance_id]: {
        az: availability_zone,
        cpu: entry.info?.cpu_percent ?? null,
        stressRemaining: entry.info?.stress_remaining_seconds ?? 0,
        seenAt: Date.now(),
      },
    }));
    castEffect(element.name, cardRef.current);
  }, []);

  useEffect(() => {
    if (paused) return;
    void poll();
    const timer = setInterval(() => void poll(), POLL_INTERVAL_MS);
    return () => clearInterval(timer);
  }, [paused, poll]);

  const reset = () => {
    setLog([]);
    setByInstance({});
    setByAz({});
    setCpuReports({});
    setFailures(0);
    setCurrent(null);
  };

  const info = current?.info;
  const element = info ? elementFor(info.availability_zone, info.instance_id) : null;
  const sortedEntries = (record: Record<string, Counter>) =>
    Object.entries(record).sort(([a], [b]) => a.localeCompare(b));

  return (
    <Panel
      letter="A"
      title="¿Qué grimorio respondió?"
      concept="ALB · Multi-AZ · Health checks"
      className="panel-wide"
      actions={
        <>
          <button className={`btn ${paused ? "btn-gold" : ""}`} onClick={() => setPaused((value) => !value)}>
            {paused ? "▶ Reanudar" : "⏸ Pausar"}
          </button>
          <button className="btn btn-ghost" onClick={reset}>
            Reiniciar
          </button>
        </>
      }
      lesson={
        <>
          las respuestas se reparten entre instancias de distintas AZ. Termina una instancia en la consola: verás
          errores en rojo hasta que el health check la marque <em>unhealthy</em>, y luego el ALB solo enviará tráfico a
          las sanas mientras el Auto Scaling Group lanza un reemplazo.
        </>
      }
    >
      <div className="responder-layout">
        <div
          ref={cardRef}
          className="responder-card"
          style={element ? { borderColor: element.color, boxShadow: `0 0 40px ${element.glow}` } : undefined}
        >
          {info && element ? (
            <div key={current.id} className="cast-in">
              <MagicCircle color={element.color} className="card-circle" />
              <div className="responder-element" style={{ color: element.color }}>
                <ElementIcon element={element.name} color={element.color} size={36} />
                <span>Grimorio de {element.label}</span>
              </div>
              <div className="responder-instance mono">{info.instance_id}</div>
              <dl className="facts">
                <dt>AZ</dt>
                <dd className="mono">{info.availability_zone}</dd>
                <dt>Hostname</dt>
                <dd className="mono">{info.hostname}</dd>
                <dt>Respondió</dt>
                <dd className="mono">
                  {formatTime(new Date(info.timestamp))} · {current.latencyMs} ms
                </dd>
                <dt>Versión</dt>
                <dd className="mono">{info.version}</dd>
              </dl>
              {isLocalAz(info.availability_zone) && (
                <p className="hint">Modo local: todas las réplicas dicen “local-az”, así que el color se asigna por instancia.</p>
              )}
            </div>
          ) : (
            <p className="muted">{paused ? "En pausa." : "Invocando al primer grimorio…"}</p>
          )}
        </div>

        <div className="tallies">
          <TallyBars title="Respuestas por instancia" items={sortedEntries(byInstance)} />
          <TallyBars title="Respuestas por AZ" items={sortedEntries(byAz)} />
          {failures > 0 && <p className="error-text">Peticiones fallidas: {failures}</p>}
        </div>

        <div className="spell-log">
          <h3>Registro de hechizos (últimos {HISTORY_SIZE})</h3>
          <ol>
            {log.map((entry) => {
              if (!entry.info) {
                return (
                  <li key={entry.id} className="log-error">
                    <span className="mono">{formatTime(entry.receivedAt)}</span>
                    <span>✗ {entry.error}</span>
                    <span className="mono">{entry.latencyMs} ms</span>
                  </li>
                );
              }
              const entryElement = elementFor(entry.info.availability_zone, entry.info.instance_id);
              return (
                <li key={entry.id}>
                  <span className="mono">{formatTime(entry.receivedAt)}</span>
                  <span className="log-who">
                    <span className="dot" style={{ background: entryElement.color }} />
                    <span className="mono">{entry.info.instance_id}</span>
                    <span className="muted">{entry.info.availability_zone}</span>
                  </span>
                  <span className="mono">{entry.latencyMs} ms</span>
                </li>
              );
            })}
          </ol>
        </div>

        <CpuGauges reports={cpuReports} />
      </div>
    </Panel>
  );
}
