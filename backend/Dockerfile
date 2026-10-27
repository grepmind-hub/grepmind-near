FROM golang:1.22-alpine AS base
WORKDIR /app
RUN apk add --no-cache postgresql-client ca-certificates && \
    addgroup -S app && adduser -S app -G app

# ---------------------------------------------------------------
# API target
# ---------------------------------------------------------------
FROM base AS api
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/api ./cmd/api
COPY internal ./internal
COPY pkg ./pkg
COPY migrations ./migrations
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o /bin/api ./cmd/api
USER app
EXPOSE 8080
ENTRYPOINT ["/bin/api"]

# ---------------------------------------------------------------
# Worker target
# ---------------------------------------------------------------
FROM base AS worker
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/worker ./cmd/worker
COPY internal ./internal
COPY pkg ./pkg
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o /bin/worker ./cmd/worker
USER app
ENTRYPOINT ["/bin/worker"]
