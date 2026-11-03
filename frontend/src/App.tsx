import { CloverEmblem } from "./components/Art";
import { CacheMirror } from "./components/CacheMirror";
import { GrimoireResponder } from "./components/GrimoireResponder";
import { ParticleCanvas } from "./components/ParticleCanvas";
import { SpellCaster } from "./components/SpellCaster";
import { StressMode } from "./components/StressMode";

// Mapa de la arquitectura: cada paso indica qué panel lo demuestra.
function ArchitectureStrip() {
  return (
    <nav className="arch-strip" aria-label="Arquitectura">
      <div className="arch-route">
        <span className="arch-node">Usuarios</span>→<span className="arch-node gold">CloudFront</span>→
        <span className="arch-node">S3 privado (OAC)</span>
        <span className="arch-tag">D</span>
      </div>
      <div className="arch-route">
        <span className="arch-path mono">/api/*</span>→<span className="arch-node gold">ALB</span>
        <span className="arch-tag">A</span>→<span className="arch-node">Auto Scaling Group · 2 AZ</span>
        <span className="arch-tag">C</span>→<span className="arch-node">API en contenedor</span>
        <span className="arch-tag">B</span>
      </div>
    </nav>
  );
}

export default function App() {
  return (
    <>
      <ParticleCanvas />
      <div className="app">
        <header className="hero">
          <CloverEmblem />
          <div>
            <h1>Grimorios en la Nube</h1>
            <p>Arquitectura web escalable y de alta disponibilidad en AWS</p>
          </div>
        </header>

        <ArchitectureStrip />

        <main className="grid">
          <GrimoireResponder />
          <SpellCaster />
          <StressMode />
          <CacheMirror />
        </main>

        <footer className="credits">
          Arte original hecho con CSS, SVG y canvas. Proyecto educativo sin afiliación con ninguna serie ni marca.
        </footer>
      </div>
    </>
  );
}
