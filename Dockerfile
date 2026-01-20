# syntax=docker/dockerfile:1
ARG PRIVAXY_BASE_PATH="/conf"

# --- Build Stage ---
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS builder
WORKDIR /app

# 1. Install system dependencies
RUN apt-get update && apt-get install -qy \
    pkg-config build-essential cmake clang libssl-dev git \
    gcc-mipsel-linux-gnu \
    g++-mipsel-linux-gnu \
    libc6-dev-mipsel-cross \
    && curl -fsSL https://deb.nodesource.com | bash - \
    && apt-get install -qy nodejs

# 2. Setup Rust Nightly for -Zbuild-std
# Required because mipsel is a Tier 3 target and does not ship with pre-compiled artifacts
RUN rustup toolchain install nightly && \
    rustup component add rust-src --toolchain nightly && \
    rustup target add wasm32-unknown-unknown

# Explicitly set the linker for the mipsel target
ENV CARGO_TARGET_MIPSEL_UNKNOWN_LINUX_GNU_LINKER=mipsel-linux-gnu-gcc
RUN cargo install trunk

# 3. Build frontend
COPY web_frontend/package*.json ./web_frontend/
WORKDIR /app/web_frontend
RUN npm ci
COPY web_frontend/ ./
RUN trunk build --release

# 4. Build backend binary
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
# Pre-build dependencies to cache them (using -Zbuild-std)
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu || true

COPY . .  
RUN cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu --bin privaxy

# --- Runtime Stage ---
# CHANGED: Use bullseye-slim because bookworm-slim lacks mipsel manifests in 2026.
FROM --platform=$TARGETPLATFORM mipsel/debian:bullseye-slim

WORKDIR /app

# Copy the binary from the specific target directory
COPY --from=builder /app/target/mipsel-unknown-linux-gnu/release/privaxy /app/privaxy

# Runtime Environment
ARG PRIVAXY_BASE_PATH="/conf"
ENV PRIVAXY_BASE_PATH="${PRIVAXY_BASE_PATH}"
ARG PRIVAXY_PROXY_PORT=8100
ARG PRIVAXY_WEB_PORT=8200

VOLUME [ "${PRIVAXY_BASE_PATH}" ]
EXPOSE ${PRIVAXY_PROXY_PORT} ${PRIVAXY_WEB_PORT}

ENTRYPOINT ["/app/privaxy"]
