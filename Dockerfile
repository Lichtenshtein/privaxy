# syntax=docker/dockerfile:1
ARG PRIVAXY_BASE_PATH="/conf"

# --- Build Stage ---
FROM --platform=$BUILDPLATFORM rust:1-sid AS builder

WORKDIR /app

# 1. Install system dependencies
RUN apt-get update && apt-get install -qy \
    pkg-config build-essential cmake clang libssl-dev git \
    gcc-mipsel-linux-gnu \
    g++-mipsel-linux-gnu \
    libc6-dev-mipsel-cross \
    ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
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
# FIRST: Copy any local dependencies required by the frontend
COPY filterlists-api /app/filterlists-api

# SECOND: Copy the frontend files
COPY web_frontend/package*.json /app/web_frontend/
WORKDIR /app/web_frontend
RUN npm ci

COPY web_frontend/ /app/web_frontend/

# Now trunk can find /app/filterlists-api/Cargo.toml
RUN trunk build --release

# 4. Build backend binary

# Set this before running cargo build because RING 16.20
# will panic when cross-compiling to mipsel because ring
# does not have pre-generated assembly or build logic for MIPS architectures
ENV RING_PREGENERATE_ASM=1

#RUN cargo fetch
#RUN cargo update -p ring:0.16.20 --precise 0.17.12

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
# Pre-build dependencies to cache them (using -Zbuild-std)
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu || true

COPY . .  
RUN cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu --bin privaxy

# --- Runtime Stage ---
# Use debootstrap-ports which contains the actual mipsel binaries.
# Standard official images no longer carry this manifest.
FROM multiarch/debian-debootstrap:mipsel-sid

WORKDIR /app

# Copy the binary from the cross-compilation target path
COPY --from=builder /app/target/mipsel-unknown-linux-gnu/release/privaxy /app/privaxy

# Runtime Environment
ARG PRIVAXY_BASE_PATH="/conf"
ENV PRIVAXY_BASE_PATH="${PRIVAXY_BASE_PATH}"
ARG PRIVAXY_PROXY_PORT=8100
ARG PRIVAXY_WEB_PORT=8200

VOLUME [ "${PRIVAXY_BASE_PATH}" ]
EXPOSE ${PRIVAXY_PROXY_PORT} ${PRIVAXY_WEB_PORT}

ENTRYPOINT ["/app/privaxy"]
