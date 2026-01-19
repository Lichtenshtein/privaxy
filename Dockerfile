# syntax=docker/dockerfile:1
ARG PRIVAXY_BASE_PATH="/conf"

# --- Build Stage ---
# Use BUILDPLATFORM (typically amd64) to avoid "no match for platform" errors
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS builder
WORKDIR /app

# Install cross-compilers and frontend tools
RUN apt-get update && apt-get install -qy \
    pkg-config build-essential cmake clang libssl-dev git \
    gcc-mipsel-linux-gnu \
    g++-mipsel-linux-gnu \
    libc6-dev-mipsel-cross \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -qy nodejs

# 1. Setup Rust for MIPS cross-compilation
# MIPS is a Tier 3 target; -Zbuild-std is required for the standard library
RUN rustup toolchain install nightly && \
    rustup component add rust-src --toolchain nightly && \
    rustup target add wasm32-unknown-unknown

# Set the linker for the mipsel target
ENV CARGO_TARGET_MIPSEL_UNKNOWN_LINUX_GNU_LINKER=mipsel-linux-gnu-gcc

# Install Trunk for frontend building
RUN cargo install trunk

# 2. Cache Rust dependencies (optional but recommended)
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo +nightly build --release -Zbuild-std --target mipsel-unknown-linux-gnu || true

# 3. Build frontend
COPY web_frontend ./web_frontend
WORKDIR /app/web_frontend
RUN npm ci && trunk build --release

# 4. Build backend binary for mipsel
WORKDIR /app
COPY . .  
RUN cargo +nightly build --release -Zbuild-std --target mipsel-unknown-linux-gnu --bin privaxy

# --- Runtime Stage ---
# Use a base image that supports linux/mipsel. Debian 13 (Trixie) supports mipsel as of 2026.
FROM --platform=linux/mipsel debian:trixie-slim

WORKDIR /app

# Ensure we copy from the specific target directory created by cross-compilation
COPY --from=builder /app/target/mipsel-unknown-linux-gnu/release/privaxy /app/privaxy

ARG PRIVAXY_BASE_PATH="/conf"
ENV PRIVAXY_BASE_PATH="${PRIVAXY_BASE_PATH}"
ARG PRIVAXY_PROXY_PORT=8100
ARG PRIVAXY_WEB_PORT=8200

VOLUME [ "${PRIVAXY_BASE_PATH}" ]
EXPOSE ${PRIVAXY_PROXY_PORT} ${PRIVAXY_WEB_PORT}
ENTRYPOINT ["/app/privaxy"]
