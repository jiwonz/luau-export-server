# luau-export-server

A web application for parsing Luau modules and extracting exported type definitions.

## Quick Start

**Prerequisites**: [Lute](https://github.com/luau-lang/lute)

**Development**:
```bash
mise run start
# or: lute src/server.luau
```

**Docker**:
```bash
docker build -t luau-export-server .
docker run -p 8080:8080 luau-export-server
```

Server runs on `http://localhost:8080` (configure with `PORT` env var).

## Features

- AST parsing for Luau modules
- Extract type aliases and type functions
- Type re-exporting from external modules
- Generic type support
- gzip compression
- Type-safe Luau code

## Development

Check types and lint:
```bash
mise run check
```
