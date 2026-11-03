// Capa de partículas a pantalla completa (canvas 2D).
// - Fondo: motas doradas y verdes que flotan lentamente.
// - Hechizos: cada elemento tiene su propia "física" para que se distingan:
//     fuego  -> brasas que suben
//     viento -> hojas que giran en espiral
//     agua   -> gotas que saltan y caen
//     tierra -> fragmentos pesados que rebotan hacia abajo
//     rayo   -> un relámpago y chispas muy rápidas
//     luz    -> estrellas que se expanden en anillo

import { useEffect, useRef } from "react";
import { ELEMENTS } from "../elements";
import { onSpellEffect, type SpellEffect } from "../effects";

type Shape = "dot" | "leaf" | "square" | "spark" | "star" | "ring";

interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  gravity: number;
  drag: number;
  size: number;
  color: string;
  life: number;
  maxLife: number;
  shape: Shape;
  rotation: number;
  spin: number;
  // Para el viento: la partícula orbita alrededor de un centro.
  orbit?: { cx: number; cy: number; angle: number; radius: number; speed: number; grow: number };
}

interface Bolt {
  points: Array<[number, number]>;
  life: number;
  color: string;
}

const MAX_PARTICLES = 1500;
const random = (min: number, max: number) => min + Math.random() * (max - min);
const pick = <T,>(items: T[]) => items[Math.floor(Math.random() * items.length)];

function ring(x: number, y: number, color: string): Particle {
  return { x, y, vx: 0, vy: 0, gravity: 0, drag: 1, size: 10, color, life: 40, maxLife: 40, shape: "ring", rotation: 0, spin: 0 };
}

function spawnSpell(effect: SpellEffect, particles: Particle[], bolts: Bolt[], scale: number): void {
  const { x, y } = effect;
  const color = ELEMENTS[effect.element].color;
  const amount = Math.round(60 * effect.intensity * scale);
  particles.push(ring(x, y, color));

  for (let i = 0; i < amount; i++) {
    const angle = random(0, Math.PI * 2);
    const base: Particle = {
      x, y, vx: 0, vy: 0, gravity: 0, drag: 0.98, size: random(2, 4), color,
      life: 0, maxLife: random(50, 90), shape: "dot", rotation: random(0, Math.PI * 2), spin: random(-0.1, 0.1),
    };

    switch (effect.element) {
      case "fuego":
        particles.push({
          ...base, x: x + random(-30, 30), vx: random(-1, 1), vy: random(-4, -1), gravity: -0.04,
          color: pick(["#ff7a3d", "#ffb347", "#ff4e2a", "#ffd84d"]), size: random(2, 5),
        });
        break;
      case "viento":
        particles.push({
          ...base, shape: "leaf", size: random(4, 7), color: pick(["#3ddc97", "#8ef0c3", "#d4af37"]),
          orbit: { cx: x, cy: y, angle, radius: random(5, 30), speed: random(0.08, 0.14), grow: random(1.2, 2.5) },
        });
        break;
      case "agua":
        particles.push({
          ...base, vx: Math.cos(angle) * random(1, 4), vy: random(-7, -2), gravity: 0.22,
          color: pick(["#4fc3f7", "#a4e4ff", "#2a8fd6"]),
        });
        break;
      case "tierra":
        particles.push({
          ...base, shape: "square", size: random(3, 7), vx: Math.cos(angle) * random(2, 6),
          vy: Math.sin(angle) * random(2, 6) - 2, gravity: 0.3, drag: 0.97,
          color: pick(["#c9955c", "#8a6239", "#e0c08a"]),
        });
        break;
      case "rayo":
        particles.push({
          ...base, shape: "spark", vx: Math.cos(angle) * random(6, 14), vy: Math.sin(angle) * random(6, 14),
          drag: 0.88, maxLife: random(15, 30), color: pick(["#ffd84d", "#fff6c2"]),
        });
        break;
      case "luz": {
        const evenAngle = (i / amount) * Math.PI * 2;
        particles.push({
          ...base, shape: "star", size: random(3, 6), vx: Math.cos(evenAngle) * random(2, 5),
          vy: Math.sin(evenAngle) * random(2, 5), drag: 0.95, color: pick(["#f3ecd6", "#d4af37", "#ffffff"]),
        });
        break;
      }
    }
  }

  // El rayo además dibuja un relámpago zigzagueante desde arriba.
  if (effect.element === "rayo") {
    const points: Array<[number, number]> = [];
    let currentX = x + random(-120, 120);
    for (let currentY = 0; currentY < y; currentY += random(25, 50)) {
      points.push([currentX, currentY]);
      currentX += random(-35, 35);
    }
    points.push([x, y]);
    bolts.push({ points, life: 14, color });
  }

  if (particles.length > MAX_PARTICLES) particles.splice(0, particles.length - MAX_PARTICLES);
}

function spawnAmbient(width: number, height: number): Particle {
  return {
    x: random(0, width), y: height + 10, vx: random(-0.2, 0.2), vy: random(-0.6, -0.2), gravity: 0, drag: 1,
    size: random(1, 2.5), color: pick(["#d4af37", "#3fa66b", "#8ef0c3"]), life: 0, maxLife: random(400, 800),
    shape: "dot", rotation: 0, spin: 0,
  };
}

function drawParticle(ctx: CanvasRenderingContext2D, p: Particle): void {
  const alpha = Math.max(0, 1 - p.life / p.maxLife);
  ctx.globalAlpha = alpha;
  ctx.fillStyle = p.color;
  ctx.strokeStyle = p.color;

  switch (p.shape) {
    case "dot":
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
      break;
    case "square":
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rotation);
      ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size);
      ctx.restore();
      break;
    case "leaf":
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rotation);
      ctx.beginPath();
      ctx.ellipse(0, 0, p.size, p.size / 2.5, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
      break;
    case "spark":
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(p.x, p.y);
      ctx.lineTo(p.x - p.vx * 2, p.y - p.vy * 2);
      ctx.stroke();
      break;
    case "star":
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rotation);
      ctx.beginPath();
      for (let i = 0; i < 8; i++) {
        const radius = i % 2 === 0 ? p.size : p.size / 3;
        const angle = (i / 8) * Math.PI * 2;
        ctx.lineTo(Math.cos(angle) * radius, Math.sin(angle) * radius);
      }
      ctx.closePath();
      ctx.fill();
      ctx.restore();
      break;
    case "ring":
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size + p.life * 3, 0, Math.PI * 2);
      ctx.stroke();
      break;
  }
}

function updateParticle(p: Particle): void {
  p.life += 1;
  p.rotation += p.spin;
  if (p.orbit) {
    p.orbit.angle += p.orbit.speed;
    p.orbit.radius += p.orbit.grow;
    p.x = p.orbit.cx + Math.cos(p.orbit.angle) * p.orbit.radius;
    p.y = p.orbit.cy + Math.sin(p.orbit.angle) * p.orbit.radius * 0.6 - p.life * 0.6;
    p.rotation = p.orbit.angle;
    return;
  }
  p.vx *= p.drag;
  p.vy = p.vy * p.drag + p.gravity;
  p.x += p.vx;
  p.y += p.vy;
}

export function ParticleCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;

    // Respeta la preferencia de "reducir movimiento" del sistema operativo.
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const scale = reducedMotion ? 0.3 : 1;

    const particles: Particle[] = [];
    const ambient: Particle[] = [];
    const bolts: Bolt[] = [];
    let width = 0;
    let height = 0;
    let frame = 0;

    const resize = () => {
      const ratio = window.devicePixelRatio || 1;
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = width * ratio;
      canvas.height = height * ratio;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    };
    resize();
    window.addEventListener("resize", resize);

    const unsubscribe = onSpellEffect((effect) => spawnSpell(effect, particles, bolts, scale));

    const tick = () => {
      ctx.clearRect(0, 0, width, height);
      ctx.globalCompositeOperation = "lighter"; // los colores se suman: efecto de brillo

      if (!reducedMotion && ambient.length < 45 && Math.random() < 0.15) {
        ambient.push(spawnAmbient(width, height));
      }

      for (const list of [ambient, particles]) {
        for (let i = list.length - 1; i >= 0; i--) {
          const p = list[i];
          updateParticle(p);
          if (p.life >= p.maxLife || p.y < -50) {
            list.splice(i, 1);
          } else {
            drawParticle(ctx, p);
          }
        }
      }

      for (let i = bolts.length - 1; i >= 0; i--) {
        const bolt = bolts[i];
        ctx.globalAlpha = bolt.life / 14;
        ctx.strokeStyle = bolt.color;
        ctx.lineWidth = 3;
        ctx.beginPath();
        bolt.points.forEach(([px, py], index) => (index === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py)));
        ctx.stroke();
        bolt.life -= 1;
        if (bolt.life <= 0) bolts.splice(i, 1);
      }

      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = "source-over";
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("resize", resize);
      unsubscribe();
    };
  }, []);

  return <canvas ref={canvasRef} className="particle-canvas" aria-hidden="true" />;
}
