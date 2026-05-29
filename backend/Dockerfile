FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/server.dart -o /app/server

# Minimal runtime image — Debian bookworm for glibc compatibility
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 \
    openssh-client \
    git \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/server /app/server

RUN useradd -r -s /bin/false openvault && \
    mkdir -p /data/vaults && \
    chown -R openvault:openvault /data && \
    chmod +x /app/server

USER openvault
WORKDIR /data

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost:8080/health | grep -q '"ok"' || exit 1

CMD ["/app/server"]
