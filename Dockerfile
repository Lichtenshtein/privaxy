# syntax=docker/dockerfile:1
ARG PRIVAXY_BASE_PATH="/conf"

# --- Build Stage ---
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS builder

WORKDIR /app

# 1. Install system dependencies (including perl)
RUN apt-get update && apt-get install -qy \
    pkg-config build-essential cmake clang libssl-dev git \
    binutils-mipsel-linux-gnu \
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

# Copy all manifests
COPY Cargo.toml Cargo.lock ./
COPY privaxy/Cargo.toml ./privaxy/
COPY filterlists-api/Cargo.toml ./filterlists-api/

# RUN cargo +nightly build --release -Zbuild-std=std,panic_unwind --target mipsel-unknown-linux-gnu || true

# Step B: Final build execution
COPY . .  

# Fetch dependencies so we can patch them
RUN cargo +nightly fetch --target mipsel-unknown-linux-gnu || true

RUN cargo update -p ring@0.17.8

# Universal patcher: finds rand.rs in all ring checkouts (git or registry)
RUN find /usr/local/cargo -name "rand.rs" | grep "ring" | while read -r file; do \
    echo "Processing: $file"; \
    # Check if this version of rand.rs needs the MIPS constant
    if grep -q "mod sysrand_chunk" "$file"; then \
        # Apply the patch if not already present
        if ! grep -q "target_arch = \"mips\"" "$file"; then \
            sed -i '/target_arch = "x86_64"\]/a \        #[cfg(any(target_arch = "mips", target_arch = "mipsel"))]\n        const SYS_GETRANDOM: c_long = 4353;' "$file"; \
        fi; \
        # VERIFICATION: Fail the build if the constant is still missing in this file
        if ! grep -q "const SYS_GETRANDOM: c_long = 4353;" "$file"; then \
            echo "ERROR: Patch failed for $file"; \
            exit 1; \
        fi; \
        echo "Successfully verified patch for $file"; \
    fi \
done

RUN find privaxy/src -name "*.rs" | while read -r file; do \
    if grep -q "Asn1Time::from_unix" "$file"; then \
        echo "Patching: $file"; \
        # Patch Case A: Wraps the complex subtraction in ( ... ) as libc::time_t
        # This converts "Asn1Time::from_unix(expr).unwrap()" to "Asn1Time::from_unix((expr) as libc::time_t).unwrap()"
        sed -i 's/Asn1Time::from_unix(\([^)]*\))/Asn1Time::from_unix((\1) as libc::time_t)/g' "$file"; \
        \
        # Patch Case B: Handles the simple 'curtime' variable in network.rs (line 238)
        # Result: Asn1Time::from_unix(curtime as libc::time_t)
        sed -i 's/Asn1Time::from_unix(curtime)/Asn1Time::from_unix(curtime as libc::time_t)/g' "$file"; \
        \
        # VERIFICATION: Fail if Asn1Time::from_unix is present but no cast was applied
        if ! grep -q "as libc::time_t" "$file"; then \
            echo "ERROR: Patch failed to apply to $file"; \
            exit 1; \
        fi; \
        echo "Verified patch for $file"; \
    fi \
done

ENV CARGO_TARGET_MIPSEL_UNKNOWN_LINUX_GNU_LINKER=mipsel-linux-gnu-gcc
ENV CC_mipsel_unknown_linux_gnu=mipsel-linux-gnu-gcc
ENV RUSTFLAGS="-C linker=mipsel-linux-gnu-gcc"
ENV AR_mipsel_unknown_linux_gnu=mipsel-linux-gnu-ar
ENV RING_CORE_NO_ASM=1

RUN RUSTC_BOOTSTRAP=1 \
    cargo +nightly build --release \
    -Zbuild-std=std,panic_unwind \
    --target mipsel-unknown-linux-gnu \
    --bin privaxy

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
