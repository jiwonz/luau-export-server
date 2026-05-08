FROM ghcr.io/luau-lang/lute:1

EXPOSE 8080

WORKDIR /app
COPY . .

CMD ["run", "src/server.luau"]
