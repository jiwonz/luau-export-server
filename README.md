# luau-export-server

A web application for parsing Luau modules and extracting exported type definitions.

## Quick Start

**Prerequisites**: [Lute](https://github.com/luau-lang/lute)

**Run Locally**:
```bash
mise start
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

[Mise](https://mise.jdx.dev/) manages the development toolchain and tasks. It automatically installs and manages Lute based on `mise.toml`.

Available tasks:

```bash
mise start   # Start the server locally with auto-reload (DEV mode enabled)
mise check   # Type check and lint src/ directory
```
