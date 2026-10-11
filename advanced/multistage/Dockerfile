# Сборочный этап содержит компилятор и исходники.
FROM golang:1.24.6-alpine AS build
WORKDIR /src
COPY main.go .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server main.go

# В финальный образ переносим только статический бинарник.
FROM scratch
COPY --from=build /out/server /server
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/server"]
