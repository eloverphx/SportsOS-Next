FROM node:22-bookworm AS build

WORKDIR /app

COPY package.json package-lock.json tsconfig.base.json ./

COPY apps/api/package.json ./apps/api/package.json
COPY apps/dashboard/package.json ./apps/dashboard/package.json
COPY packages/config/package.json ./packages/config/package.json
COPY packages/core/package.json ./packages/core/package.json

RUN npm ci --no-audit --no-fund

COPY apps/dashboard ./apps/dashboard
COPY packages/config ./packages/config
COPY packages/core ./packages/core

WORKDIR /app/apps/dashboard

ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run typecheck
RUN npm run build


FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=4000
ENV HOSTNAME=0.0.0.0

WORKDIR /app

COPY --from=build /app/apps/dashboard/.next/standalone ./
COPY --from=build /app/apps/dashboard/.next/static ./apps/dashboard/.next/static

USER node

EXPOSE 4000

CMD ["node", "apps/dashboard/server.js"]