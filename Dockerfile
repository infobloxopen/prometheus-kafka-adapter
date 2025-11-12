# Build stage
FROM golang:1.25-alpine3.21 AS builder
LABEL stage=builder-intermediate
WORKDIR /src/prometheus-kafka-adapter

# Install build dependencies for confluent-kafka-go (requires librdkafka)
RUN apk add --no-cache gcc musl-dev pkgconfig bash

# Install librdkafka for confluent-kafka-go
RUN apk add --no-cache librdkafka-dev

# Copy go mod files first for better caching
COPY go.mod go.sum ./
COPY vendor ./vendor

# Copy source code
COPY *.go ./
COPY schemas ./schemas

# Build the binary with optimizations for distroless
# CGO is enabled because confluent-kafka-go requires it
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w" \
    -tags musl,static_all \
    -mod=vendor \
    -o /bin/prometheus-kafka-adapter

# Final runtime stage using distroless base (not static, as we need libc)
FROM gcr.io/distroless/base-debian13:nonroot-amd64 AS runner
WORKDIR /

# Copy the binary from builder
COPY --from=builder /bin/prometheus-kafka-adapter /prometheus-kafka-adapter

# Copy schema file
COPY --from=builder /src/prometheus-kafka-adapter/schemas/metric.avsc /schemas/metric.avsc

# Use nonroot user for security
USER nonroot

ENTRYPOINT ["/prometheus-kafka-adapter"]
