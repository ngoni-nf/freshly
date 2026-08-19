# ---------------------------------------------------------------------------
# Freshly API.
#
# The repository is an npm workspace, so the build stage needs the root
# package-lock and both workspace manifests before it can install anything.
# Copying the whole tree first would invalidate the layer on every source edit.
#
# Node rather than a serverless runtime, deliberately: dispatch holds in-process
# timers across a 60-second offer wave and the realtime gateway holds websocket
# connections open. Neither survives a function that is killed between requests.
# ---------------------------------------------------------------------------
FROM node:22-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/
COPY packages/contracts/package.json packages/contracts/

RUN npm ci

COPY tsconfig*.json ./
COPY packages/contracts packages/contracts
COPY apps/api apps/api

RUN npm run build -w @freshly/contracts \
 && npm run build -w @freshly/api

# Drop dev dependencies from the tree we are about to copy forward.
RUN npm prune --omit=dev


FROM node:22-alpine AS runtime

WORKDIR /app
ENV NODE_ENV=production

# Migrations ship with the image so a release can apply its own schema change
# rather than depending on someone remembering to run it first.
# Only the root node_modules. npm workspaces hoist everything it can to the
# root, so apps/api/node_modules exists only when a dependency could not be
# hoisted — a version conflict with another workspace. There is none here, so
# the directory is absent and COPYing it fails the build outright rather than
# being skipped. Copying the root alone is both correct and sufficient:
# resolution walks up from apps/api/dist and finds it.
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/apps/api/dist ./apps/api/dist
COPY --from=build /app/apps/api/package.json ./apps/api/package.json
COPY --from=build /app/packages/contracts/dist ./packages/contracts/dist
COPY --from=build /app/packages/contracts/package.json ./packages/contracts/package.json
COPY --from=build /app/package.json ./package.json
COPY infra/db ./infra/db

# Never run as root. A container that is compromised should not also be
# privileged inside its own filesystem.
USER node

EXPOSE 3000

# The platform's health check hits /health; this one catches a container that
# is up but cannot serve, which is the case a TCP check misses.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "apps/api/dist/main.js"]
