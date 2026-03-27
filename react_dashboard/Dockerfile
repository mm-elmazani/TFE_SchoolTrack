# ============================================================================
# Multi-stage build : React (Vite) → Nginx
# ============================================================================

# --- Stage 1 : Build ---
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .
RUN npm run build

# --- Stage 2 : Serve ---
FROM nginx:1.27-alpine

# Config Nginx SPA (fallback index.html pour le routing React)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copier le build Vite
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
