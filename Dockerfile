# Use the architecture-specific debootstrap ports for the runtime
FROM multiarch/debian-debootstrap:mipsel-sid-slim

WORKDIR /app

# Copy the binary directly from the host (where cross built it)
COPY target/mipsel-unknown-linux-gnu/release/privaxy /app/privaxy

ARG PRIVAXY_BASE_PATH="/conf"
ENV PRIVAXY_BASE_PATH="${PRIVAXY_BASE_PATH}"
VOLUME [ "${PRIVAXY_BASE_PATH}" ]
EXPOSE 8100 8200

ENTRYPOINT ["/app/privaxy"]
