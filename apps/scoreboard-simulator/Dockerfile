FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY apps/scoreboard-simulator/package.json ./package.json
COPY apps/scoreboard-simulator/src ./src

USER node

EXPOSE 4020

CMD ["node", "src/index.js"]
