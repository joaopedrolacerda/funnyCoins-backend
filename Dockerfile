# Backend em produção: só a API. O site é outro serviço, no repositório funnycoins.
# O Railway usa este arquivo pelo railway.json. As variáveis estão em "Publicar" na CLAUDE.md.

# 1. Build
FROM rust:1-bookworm AS build
WORKDIR /rust
COPY rust/ ./
RUN cargo build --release -p myapp-backend

# 2. Imagem final, só com o binário
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 myapp
WORKDIR /app
COPY --from=build /rust/target/release/myapp-backend /app/myapp-backend
ENV RUST_LOG=info,tower_http=info
USER myapp
EXPOSE 8080
CMD ["/app/myapp-backend"]
