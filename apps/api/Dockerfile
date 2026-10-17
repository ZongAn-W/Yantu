FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/package.json
RUN npm ci --workspace @planner/api --include-workspace-root
COPY tsconfig.json ./tsconfig.json
COPY apps/api/tsconfig.json apps/api/tsconfig.json
COPY apps/api/src apps/api/src
RUN npm run build -w @planner/api

FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/package.json
RUN npm ci --workspace @planner/api --include-workspace-root --omit=dev
COPY --from=build /app/apps/api/dist apps/api/dist
COPY apps/api/db/migrations apps/api/db/migrations
WORKDIR /app/apps/api
CMD ["node", "dist/server.js"]
