# syntax=docker/dockerfile:1.7
FROM node:22-bookworm

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    procps hostname curl git openssl python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

# Enable corepack
RUN corepack enable

WORKDIR /app

# Copy package files first for better caching
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches

# Create extensions directories if they don't exist
RUN mkdir -p extensions src/zero-token/extensions

# Install dependencies without cache mounts
RUN NODE_OPTIONS=--max-old-space-size=2048 pnpm install --frozen-lockfile --no-optional

# Copy the rest of the application
COPY . .

# Fix extension permissions
RUN for dir in /app/extensions /app/src/zero-token/extensions /app/.agent /app/.agents; do \
      if [ -d "$dir" ]; then \
        find "$dir" -type d -exec chmod 755 {} +; \
        find "$dir" -type f -exec chmod 644 {} +; \
      fi; \
    done

# Build A2UI bundle (non-fatal if fails)
RUN pnpm canvas:a2ui:bundle || (echo "A2UI bundle stub created" && \
    mkdir -p src/canvas-host/a2ui && \
    echo "/* A2UI bundle stub */" > src/canvas-host/a2ui/a2ui.bundle.js)

# Build the application
RUN pnpm build:docker
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# Install Chromium for browser automation (optional but recommended)
RUN npx playwright install --with-deps chromium || true

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash openclaw && \
    chown -R openclaw:openclaw /app

# Switch to non-root user
USER openclaw

ENV NODE_ENV=production
ENV PORT=8080
ENV HOST=0.0.0.0

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD node -e "fetch('http://localhost:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--bind", "lan", "--port", "8080"]
