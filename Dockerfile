# Build stage - use Debian-based Go image to match distroless base
FROM golang:1.25.11-bookworm AS builder
LABEL stage=builder-intermediate
WORKDIR /src/prometheus-kafka-adapter

# Install build dependencies for musl/CGO build
RUN apk add --no-cache \
    gcc \
    musl-dev

# Copy go mod files first for better caching
COPY go.mod go.sum ./
COPY vendor ./vendor

# Copy source code
COPY *.go ./
COPY schemas ./schemas

# Build static musl binary
# CGO is enabled because confluent-kafka-go requires it
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build \
    -tags "musl,static,netgo" \
    -ldflags='-s -w -extldflags "-static"' \
    -mod=vendor \
    -o /bin/prometheus-kafka-adapter

# Final runtime stage using distroless static base
FROM gcr.io/distroless/static-debian13:nonroot-amd64 AS runner
WORKDIR /

# Copy the binary from builder
COPY --from=builder /bin/prometheus-kafka-adapter /prometheus-kafka-adapter

# Copy schema file
COPY --from=builder /src/prometheus-kafka-adapter/schemas/metric.avsc /schemas/metric.avsc

# Use nonroot user for security
USER nonroot

ENTRYPOINT ["/prometheus-kafka-adapter"]
