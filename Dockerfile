# syntax=docker/dockerfile:1
ARG PRIVAXY_BASE_PATH="/conf"

# --- Build Stage ---
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS builder

WORKDIR /app

# 1. Install system dependencies
# Added 'perl' (Required by ring 0.17.8 for assembly)
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
WORKDIR /app_frontend
WORKDIR /app/web_frontend
RUN npm ci
COPY web_frontend/ /app/web_frontend/
RUN trunk build --release

# 4. Build backend binary
WORKDIR /app
COPY Cargo.toml Cargo.lock ./

# IMPORTANT: RING 0.17.8 logic. 
# We set PREGENERATE_ASM to 1, but we must ensure the target dir is clean 
# between the dummy build and the real build to avoid the "File exists" panic.
ENV RING_PREGENERATE_ASM=1

# Dummy build to cache dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu || true

# Copy source code
COPY . .  

# FIX: Remove the ring build artifacts from the dummy run to prevent 
# the "Os { code: 17, kind: AlreadyExists }" error during the final build.
RUN rm -rf target/mipsel-unknown-linux-gnu/release/build/ring-*

RUN cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu --bin privaxy

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
