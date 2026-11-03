import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// En desarrollo (npm run dev) Vite reenvía /api a localhost:8080, igual que
// CloudFront reenvía /api/* al ALB en AWS. En 8080 puede estar:
//   - el stack de docker compose (su nginx a su vez reenvía a la API), o
//   - la API sola:  docker run -p 8080:8080 grimorio-api
// Así el código del frontend siempre usa rutas relativas (/api/...) y no necesita CORS.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:8080",
    },
  },
});
