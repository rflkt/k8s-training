# Simple Dockerfile for the k8s-training API
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG APP_VERSION=1.0
RUN go build -ldflags="-X main.version=${APP_VERSION}" -o api .

FROM alpine:3.19

WORKDIR /app
COPY --from=builder /app/api .

EXPOSE 8080

CMD ["./api"]
