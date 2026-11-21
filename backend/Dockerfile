FROM golang:1.26-alpine AS base
WORKDIR /app
RUN apk add --no-cache postgresql-client ca-certificates tzdata gcc musl-dev && \
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
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -trimpath -o /bin/api ./cmd/api
USER app
EXPOSE 8080
ENTRYPOINT ["/bin/api"]

# ---------------------------------------------------------------
# Isolated QA OTP inbox helper. This is deliberately the only process in this
# target running as root; its tmpfs inbox is root-owned mode 0700. It is not
# exposed through the API or the public Nginx routes.
# ---------------------------------------------------------------
FROM base AS qa-otp-inbox
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/qa-otp-inbox ./cmd/qa-otp-inbox
COPY internal/qaotpinbox ./internal/qaotpinbox
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -trimpath -o /bin/qa-otp-inbox ./cmd/qa-otp-inbox
EXPOSE 8090
ENTRYPOINT ["/bin/qa-otp-inbox"]

# ---------------------------------------------------------------
# Worker target
# ---------------------------------------------------------------
FROM base AS worker
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/worker ./cmd/worker
COPY internal ./internal
COPY pkg ./pkg
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -trimpath -o /bin/worker ./cmd/worker
USER app
ENTRYPOINT ["/bin/worker"]
