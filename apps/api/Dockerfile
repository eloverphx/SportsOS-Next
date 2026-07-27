FROM node:22-bookworm AS build

WORKDIR /app

COPY package.json package-lock.json tsconfig.base.json ./

COPY apps/api/package.json ./apps/api/package.json
COPY apps/dashboard/package.json ./apps/dashboard/package.json
COPY packages/config/package.json ./packages/config/package.json
COPY packages/core/package.json ./packages/core/package.json

RUN npm ci --no-audit --no-fund

COPY apps/api ./apps/api
COPY packages/config ./packages/config
COPY packages/core ./packages/core

RUN npm run build --workspace=@sportsos/core \
 && npm run build --workspace=@sportsos/config \
 && npm run build --workspace=@sportsos/api


FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production

WORKDIR /app

COPY package.json package-lock.json ./
COPY apps/api/package.json ./apps/api/package.json
COPY apps/dashboard/package.json ./apps/dashboard/package.json
COPY packages/config/package.json ./packages/config/package.json
COPY packages/core/package.json ./packages/core/package.json

# Install the production workspace dependency tree in the runtime image.
RUN npm ci --omit=dev --no-audit --no-fund

COPY --from=build /app/apps/api/dist ./apps/api/dist
COPY --from=build /app/packages/config/dist ./packages/config/dist
COPY --from=build /app/packages/core/dist ./packages/core/dist

USER node

EXPOSE 4001

CMD ["node", "apps/api/dist/server.js"]
