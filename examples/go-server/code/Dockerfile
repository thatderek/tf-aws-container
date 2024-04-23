FROM golang:1.21 as Builder

WORKDIR /app

COPY go.mod ./

RUN go mod download

COPY . ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /opt/app

FROM alpine:latest

COPY --from=Builder /opt/app /opt/app

EXPOSE 8080

ENV APP_EXAMPLE_STRING "Default Dockerfile string"

ENTRYPOINT ["/opt/app"]
