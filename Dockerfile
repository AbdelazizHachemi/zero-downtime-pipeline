# Pinned digest recorded in the README after the first local build.
# node:22-alpine as of 2026-09-29 on this machine.
FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 AS build
WORKDIR /app
COPY app/package.json app/package-lock.json ./
RUN npm ci
COPY app/tsconfig.json app/tsconfig.build.json ./
COPY app/src ./src
RUN npm run build

FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2
WORKDIR /app
ENV NODE_ENV=production
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules /opt/yarn-v* \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
      /usr/local/bin/yarn /usr/local/bin/yarnpkg \
    && apk upgrade --no-cache
COPY --from=build /app/dist ./dist
ARG GIT_SHA=dev
ARG BUILT_AT=unknown
ENV GIT_SHA=$GIT_SHA
ENV BUILT_AT=$BUILT_AT
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
