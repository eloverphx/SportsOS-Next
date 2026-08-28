FROM node:22-alpine

WORKDIR /app

# Install runtime dependencies from the simulator's own package manifest.
# Keeping this package-local prevents workspace pruning from omitting mqtt.
COPY apps/scoreboard-simulator/package.json ./package.json
RUN npm install --omit=dev --no-audit --no-fund

COPY apps/scoreboard-simulator/src ./src

ENV NODE_ENV=production

USER node

EXPOSE 4020

CMD ["node", "src/index.js"]
