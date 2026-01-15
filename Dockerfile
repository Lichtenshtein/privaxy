# syntax=docker/dockerfile:1

ARG PRIVAXY_BASE_PATH="/conf"

FROM rust:1 AS builder
WORKDIR /app

RUN rustup target add wasm32-unknown-unknown && \
    cargo binstall -y trunk

RUN apt-get update && apt-get install -qy \
    pkg-config \
    build-essential \
    cmake \
    clang \
    libssl-dev \
    git && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -qy nodejs

# Cache Rust dependencies
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo build --release || true

# Build frontend
COPY web_frontend ./web_frontend
WORKDIR /app/web_frontend
RUN npm ci && trunk build --release

# Build backend
WORKDIR /app
COPY .  .  
RUN cargo build --release

FROM gcr.io/distroless/cc-debian13:nonroot

COPY --from=builder /app/target/release/privaxy /app/privaxy

ARG PRIVAXY_BASE_PATH="/conf"
ENV PRIVAXY_BASE_PATH="${PRIVAXY_BASE_PATH}"
ARG PRIVAXY_PROXY_PORT=8100
ARG PRIVAXY_WEB_PORT=8200

VOLUME [ "${PRIVAXY_BASE_PATH}" ]
EXPOSE ${PRIVAXY_PROXY_PORT} ${PRIVAXY_WEB_PORT}
WORKDIR /app
ENTRYPOINT ["/app/privaxy"]
