# Build stage - use Debian-based Go image to match distroless base
FROM golang:1.22.3-bookworm AS builder
LABEL stage=builder-intermediate
WORKDIR /src/prometheus-kafka-adapter

# Install build dependencies for confluent-kafka-go (requires librdkafka)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    pkg-config \
    librdkafka-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy go mod files first for better caching
COPY go.mod go.sum ./
COPY vendor ./vendor

# Copy source code
COPY *.go ./
COPY schemas ./schemas

# Build the binary
# CGO is enabled because confluent-kafka-go requires it
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w" \
    -mod=vendor \
    -o /bin/prometheus-kafka-adapter

# Final runtime stage using distroless base with glibc
FROM gcr.io/distroless/base-debian13:nonroot-amd64 AS runner
WORKDIR /

# Copy required shared libraries from builder
COPY --from=builder /usr/lib/x86_64-linux-gnu/librdkafka.so.1 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libsasl2.so.2 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/liblz4.so.1 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libzstd.so.1 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libssl.so.3 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /usr/lib/x86_64-linux-gnu/

# Copy the binary from builder
COPY --from=builder /bin/prometheus-kafka-adapter /prometheus-kafka-adapter

# Copy schema file
COPY --from=builder /src/prometheus-kafka-adapter/schemas/metric.avsc /schemas/metric.avsc

# Use nonroot user for security
USER nonroot

ENTRYPOINT ["/prometheus-kafka-adapter"]
