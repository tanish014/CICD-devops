FROM node:20-alpine
WORKDIR /app

# Install production dependencies first so this layer is cached between builds.
COPY package*.json ./
RUN npm ci --omit=dev

COPY server.js ./
COPY public ./public

# Build metadata, injected by Jenkins and surfaced on the dashboard and in /metrics.
ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_NUMBER=local
ARG IMAGE_TAG=n/a
ENV APP_VERSION=$APP_VERSION GIT_COMMIT=$GIT_COMMIT BUILD_NUMBER=$BUILD_NUMBER IMAGE_TAG=$IMAGE_TAG

USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:3000/healthz || exit 1
CMD ["node", "server.js"]
