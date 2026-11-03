# Frontend: build con Node y servido con nginx (para desarrollo local).
# En AWS no se usa este contenedor: el contenido de dist/ se sube a S3
# y lo sirve CloudFront (ver scripts/deploy-frontend.sh).

# ---------- Etapa 1: compilar ----------
FROM node:26-alpine AS build
WORKDIR /app

# Primero solo package*.json para cachear la instalación de dependencias.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# ---------- Etapa 2: servir ----------
FROM nginx:1.30-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
