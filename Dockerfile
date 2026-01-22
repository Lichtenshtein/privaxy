# syntax=docker/dockerfile:1
ARG PRIVAXY_BASE_PATH="/conf"

# --- Build Stage ---
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS builder

WORKDIR /app

# 1. Install system dependencies
RUN apt-get update && apt-get install -qy \
    pkg-config build-essential cmake clang libssl-dev git \
    ca-certificates curl gnupg perl xz-utils \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -qy nodejs

# 2. Download and install mipsel-linux-musl toolchain (musl.cc)
RUN curl -L https://musl.cc/mipsel-linux-musl-cross.tgz -o toolchain.tgz \
    && tar -xf toolchain.tgz -C /opt \
    && rm toolchain.tgz
ENV PATH="/opt/mipsel-linux-musl-cross/bin:${PATH}"

# 3. Setup Rust Nightly
RUN rustup toolchain install nightly && \
    rustup component add rust-src --toolchain nightly && \
    rustup target add wasm32-unknown-unknown

RUN cargo install trunk

# 4. Build frontend
COPY filterlists-api /app/filterlists-api
COPY web_frontend/package*.json /app/web_frontend/
WORKDIR /app/web_frontend
RUN npm ci
COPY web_frontend/ /app/web_frontend/
RUN trunk build --release

# 5. Build backend binary
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY privaxy/Cargo.toml ./privaxy/
COPY filterlists-api/Cargo.toml ./filterlists-api/

COPY . .  

# Fetch and Patch Ring (MIPS constant)
RUN cargo +nightly fetch --target mipsel-unknown-linux-musl || true
RUN find /usr/local/cargo -name "rand.rs" | grep "ring" | while read -r file; do \
    if grep -q "mod sysrand_chunk" "$file" && ! grep -q "target_arch = \"mips\"" "$file"; then \
        sed -i '/target_arch = "x86_64"\]/a \        #[cfg(any(target_arch = "mips", target_arch = "mipsel"))]\n        const SYS_GETRANDOM: c_long = 4353;' "$file"; \
        grep -q "const SYS_GETRANDOM: c_long = 4353;" "$file" || exit 1; \
        echo "Verified Ring patch: $file"; \
    fi \
done

# NOTE: The Asn1Time patch is REMOVED because musl 1.2.5+ uses 64-bit time_t.
# Compilation for musl targets in 2026 should work with the original code.

# Toolchain configuration for musl
ENV CARGO_TARGET_MIPSEL_UNKNOWN_LINUX_MUSL_LINKER=mipsel-linux-musl-gcc
ENV CC_mipsel_unknown_linux_musl=mipsel-linux-musl-gcc
ENV AR_mipsel_unknown_linux_musl=mipsel-linux-musl-ar
ENV RING_CORE_NO_ASM=1

RUN RUSTC_BOOTSTRAP=1 \
    cargo +nightly build --release \
    -Zbuild-std=std,panic_unwind \
    --target mipsel-unknown-linux-musl \
    --bin privaxy

# --- Runtime Stage (Static Binary) ---
# Using Alpine for 2026 to ensure small size and musl compatibility
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/target/mipsel-unknown-linux-musl/release/privaxy /app/privaxy

ARG PRIVAXY_BASE_PATH="/conf"
ENV PRIVAXY_BASE_PATH="${PRIVAXY_BASE_PATH}"
ARG PRIVAXY_PROXY_PORT=8100
ARG PRIVAXY_WEB_PORT=8200

VOLUME [ "${PRIVAXY_BASE_PATH}" ]
EXPOSE ${PRIVAXY_PROXY_PORT} ${PRIVAXY_WEB_PORT}
ENTRYPOINT ["/app/privaxy"]
