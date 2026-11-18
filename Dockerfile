# Imagem única para produção: o backend em Rust serve a API e o site já gerado.
# O Railway usa este arquivo pelo railway.json. As variáveis estão em "Publicar" na CLAUDE.md.

# 1. Site (Svelte + WASM das regras, que já vem pronto em web/src/lib/rules/pkg)
FROM node:24-bookworm-slim AS web
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

# 2. Backend
FROM rust:1-bookworm AS backend
WORKDIR /rust
COPY rust/ ./
RUN cargo build --release -p myapp-backend

# 3. Imagem final, só com o binário e o site
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 myapp
WORKDIR /app
COPY --from=backend /rust/target/release/myapp-backend /app/myapp-backend
COPY --from=web /web/dist /app/site
ENV STATIC_DIR=/app/site \
    RUST_LOG=info,tower_http=info
USER myapp
EXPOSE 8080
CMD ["/app/myapp-backend"]
