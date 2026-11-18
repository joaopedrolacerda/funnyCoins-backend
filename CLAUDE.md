# MyApp: backend (API em Rust)

API de sincronização e login do MyApp, um app de finanças pessoais gamificadas com um bichinho virtual.

Este repositório é só o backend. O projeto tem três repositórios, normalmente lado a lado em `~/Documents/funnycoins/`:
- `app/`: app SwiftUI, em `joaopedrolacerda/funnyCoins-app`.
- `backend/`: este, em `joaopedrolacerda/funnyCoins-backend`.
- `web/`: site em Svelte, em `joaopedrolacerda/funnycoins`.

## Regras obrigatórias
- **Toda mudança vem com testes, e todos os testes precisam passar** antes de dar a tarefa por concluída.
- Dinheiro trafega em centavos (inteiros). Datas trafegam em milissegundos.
- Mensagens para o usuário em português do Brasil.

## Como validar
O Rust fica em `~/.cargo/bin`. Se `cargo` não for encontrado, rode `export PATH="$HOME/.cargo/bin:$PATH"`.
- **Testes**: `cd rust && cargo test`. Os testes usam o PostgreSQL local.
  - O PostgreSQL roda com `brew services start postgresql@17`.
  - O papel `myapp` tem `CREATEDB` e é dono do banco `myapp`.
  - O `DATABASE_URL` padrão fica em `rust/.cargo/config.toml`.
  - Cada `#[sqlx::test]` cria um banco temporário próprio.
- **Lint**: `cargo clippy --all-targets` e `cargo fmt`, com largura de 120 definida em `rustfmt.toml`.
- **Imagem**: `docker build -t funnycoins-backend:local .` (o Docker fica em `/Applications/Docker.app/Contents/Resources/bin`).

## Rodar localmente
- `cd rust && ALLOW_DEV_LOGIN=true cargo run -p myapp-backend` sobe a API na porta 8080.
- O site (repositório `web`) roda com `npm run dev` na porta 5173 e repassa `/v1` e `/health` para cá.
- Opcional: com `STATIC_DIR` apontando para um `dist` do site, o backend também serve o site na mesma porta.
  Caminhos que não são arquivos devolvem o `index.html`. Rotas desconhecidas em `/v1` respondem 404 em JSON.
  Em produção isso não é usado: o site é outro serviço.

## Publicar (Railway)
- Projeto `charismatic-essence`, com dois serviços e um banco PostgreSQL:
  - `funnycoins`: esta API, em https://funnycoins-production.up.railway.app
  - o site, que tem seu próprio Dockerfile no repositório `web`.
- `Dockerfile` compila só o backend. `railway.json` aponta para ele e usa `/health` como verificação.
- Para publicar de novo: `railway up --service funnycoins --ci`, desta pasta.
  - Sem git conectado, o `railway up` usa o `.railwayignore`. Sem ele, o envio inclui `rust/target` e passa de 1 GB.
- Variáveis do serviço:
  - `DATABASE_URL=${{Postgres.DATABASE_URL}}`
  - `CLIENT_IP_HEADER=x-real-ip`
  - `CORS_ORIGINS` com o endereço do site (separado por vírgulas, se houver mais de um).
  - Não defina `ALLOW_DEV_LOGIN` nem `STATIC_DIR` em produção.
  - O Railway define `PORT` sozinho.
- As migrações rodam sozinhas ao iniciar.

## Arquitetura
```
rust/                     workspace Cargo
  backend/                Axum + SQLx + PostgreSQL
    migrations/           esquema: users, identities, sessions, records
    src/lib.rs            configuração (variáveis), rotas, CORS, site estático opcional
    src/sync.rs           POST /v1/sync
    src/auth.rs           login (código da conta, Apple, Google, dev), sessões, logout, exclusão de conta
    src/identity.rs       validação dos JWT da Apple e do Google
    src/limit.rs          limite de tentativas por IP
    tests/api.rs          testes da API contra o Postgres; keys/ tem a chave RSA só de teste
```

- A pasta `rust/rules` (regras do jogo em Rust, compiladas para o WASM do site) sumiu em 13/11/2026 e saiu do workspace.
  O site usa o WASM já gerado, que fica no repositório dele.
- Autenticação pelo cabeçalho `Authorization: Bearer <token>`, sem cookies. Por isso o site pode ficar em outra origem, só com CORS.
- Variáveis: `DATABASE_URL`, `BIND` (ou só `PORT`), `APPLE_CLIENT_IDS`, `GOOGLE_CLIENT_IDS`, `ALLOW_DEV_LOGIN`,
  `CORS_ORIGINS`, `STATIC_DIR` e `CLIENT_IP_HEADER`.

### Login
- **Principal: código da conta.**
  - `POST /v1/auth/code/new` cria a conta e devolve um código como `K7QM-4XPA-9RTD`.
    São 12 caracteres de um alfabeto sem letras que se confundem (`23456789ABCDEFGHJKMNPQRSTWXYZ`).
  - `POST /v1/auth/code` entra com o código. Aceita minúsculas, espaços e hífens.
  - O servidor guarda só o hash SHA-256, em `identities` com `provider = 'code'`. Quem perder o código perde o acesso.
  - O formato precisa ser igual ao de `web/src/lib/accountCode.ts`, no repositório do site.
- Apple e Google: prontos, mas sem client IDs configurados ainda.
- Excluir a conta apaga os dados no servidor.

### Limite de tentativas
Por IP e em memória (`src/limit.rs`):
- criar conta: 10 por hora;
- entrar com código: 30 a cada 15 minutos.
Atrás de um proxy, defina `CLIENT_IP_HEADER` (no Railway, `x-real-ip`). Sem isso, todos parecem vir do IP do proxy.

### Sincronização
- Todo registro tem `syncID`, `updatedAt` e `deletedAt`. Exclusão é só marcação (`deletedAt`).
- Conflitos: vence o `updatedAt` mais recente.
- Dinheiro em centavos, datas em milissegundos.

## Decisões em aberto
- Client IDs da Apple (Services ID para o site) e do Google.
- Login com Apple no site: o backend já aceita o token, mas o site ainda não tem o botão.
- Dois aparelhos que fizerem o cadastro inicial antes de sincronizar vão criar dois perfis. Definir se os perfis devem ser mesclados.
