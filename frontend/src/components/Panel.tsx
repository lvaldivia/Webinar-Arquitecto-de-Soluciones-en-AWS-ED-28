// Contenedor común de cada panel: título, concepto de AWS que enseña y
// una nota de "qué observar" para guiar la demo.

import type { ReactNode } from "react";

interface PanelProps {
  letter: string;
  title: string;
  concept: string;
  lesson: ReactNode;
  className?: string;
  actions?: ReactNode;
  children: ReactNode;
}

export function Panel({ letter, title, concept, lesson, className = "", actions, children }: PanelProps) {
  return (
    <section className={`panel ${className}`}>
      <header className="panel-header">
        <div>
          <span className="panel-letter">{letter}</span>
          <h2>{title}</h2>
          <span className="concept-badge">{concept}</span>
        </div>
        {actions && <div className="panel-actions">{actions}</div>}
      </header>
      <div className="panel-body">{children}</div>
      <footer className="lesson">
        <strong>Qué observar:</strong> {lesson}
      </footer>
    </section>
  );
}
