# syntax=docker/dockerfile:1
ARG PRIVAXY_BASE_PATH="/conf"

# --- Build Stage ---
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS builder

WORKDIR /app

# 1. Install system dependencies (including perl)
RUN apt-get update && apt-get install -qy \
    pkg-config build-essential cmake clang libssl-dev git \
    gcc-mipsel-linux-gnu \
    g++-mipsel-linux-gnu \
    libc6-dev-mipsel-cross \
    ca-certificates curl gnupg perl \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -qy nodejs

# 2. Setup Rust Nightly
RUN rustup toolchain install nightly && \
    rustup component add rust-src --toolchain nightly && \
    rustup target add wasm32-unknown-unknown

ENV CARGO_TARGET_MIPSEL_UNKNOWN_LINUX_GNU_LINKER=mipsel-linux-gnu-gcc
RUN cargo install trunk

# 3. Build frontend
COPY filterlists-api /app/filterlists-api
COPY web_frontend/package*.json /app/web_frontend/
WORKDIR /app/web_frontend
RUN npm ci
COPY web_frontend/ /app/web_frontend/
RUN trunk build --release

# 4. Build backend binary
WORKDIR /app

COPY Cargo.toml Cargo.lock ./

# Required for ring cross-compilation
ENV RING_PREGENERATE_ASM=1

# Step A: Cache dependencies with dummy build
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu || true

COPY . .  
RUN rm -rf target/mipsel-unknown-linux-gnu/release/build/ring-* && \
    cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu --bin privaxy

# --- Runtime Stage ---
FROM multiarch/debian-debootstrap:mipsel-bullseye-slim
WORKDIR /app
COPY --from=builder /app/target/mipsel-unknown-linux-gnu/release/privaxy /app/privaxy

ARG PRIVAXY_BASE_PATH="/conf"
ENV PRIVAXY_BASE_PATH="${PRIVAXY_BASE_PATH}"
ARG PRIVAXY_PROXY_PORT=8100
ARG PRIVAXY_WEB_PORT=8200

VOLUME [ "${PRIVAXY_BASE_PATH}" ]
EXPOSE ${PRIVAXY_PROXY_PORT} ${PRIVAXY_WEB_PORT}
ENTRYPOINT ["/app/privaxy"]
