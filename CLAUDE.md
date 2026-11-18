# MyApp: finanças pessoais gamificadas

App de gestão financeira em formato de jogo, com um bichinho virtual estilo Tamagotchi.
A base de tudo é a **reserva de emergência**: só depois dela a pessoa passa a investir.

- Plataformas: iOS, iPadOS, macOS e visionOS 27, num único target multiplataforma.
- Stack: SwiftUI + SwiftData. Sem Combine, use async/await.
- Isolamento padrão: `MainActor`, tanto no app quanto nos testes.
- Idioma do app: português do Brasil.

## Regras obrigatórias

1. **Toda mudança vem com testes, e todos os testes precisam passar** antes de dar a tarefa por concluída.
   - Use Swift Testing (`import Testing`, `@Test`, `#expect`). Não use XCTest em testes novos.
   - Regras de negócio ficam fora das views, em `Models/`, para poderem ser testadas.
     Se uma regra nascer dentro de uma view, mova-a para o motor antes de testar.
     Exemplo: `GameSnapshot.suggestedSplit`.
2. **Dinheiro sempre no formato brasileiro**, como `R$ 1.234,56`, independente do idioma do aparelho.
   - Para exibir, use `valor.brl`.
   - Para digitar, use `CurrencyField` ou `TextField(..., format: BRFormat.currency)`.
   - Nunca use `.currency(code:)` direto nem `Double` para valores monetários. Dinheiro é `Decimal`.
   - A raiz do app injeta `.environment(\.locale, BRFormat.locale)` para números e porcentagens.
3. Textos de interface em português, com tom amigável e de jogo.
4. Não force unwrap. Prefira `??`, `guard` e, nos testes, `try #require`.

## Como validar

- Compilar: `BuildProject`, a ferramenta de build do Xcode.
- Testar: `RunAllTests`. O esquema compartilhado `MyApp` inclui o target `MyAppTests`.
- Se o teste acusar um símbolo inexistente que existe no app, compile o app primeiro.
  O target de testes não tem dependência explícita do app.
  O esquema compila em série para evitar isso.
- Previews ajudam a verificar o visual com `RenderPreview`.

### Rust e site
O Rust fica em `~/.cargo/bin`. Se `cargo` não for encontrado, rode `export PATH="$HOME/.cargo/bin:$PATH"`.
- **Rust**: `cd rust && cargo test`. Os testes do backend usam o PostgreSQL local.
  - O PostgreSQL roda com `brew services start postgresql@17`.
  - O papel `myapp` tem `CREATEDB` e é dono do banco `myapp`.
  - O `DATABASE_URL` padrão fica em `rust/.cargo/config.toml`.
  - Cada `#[sqlx::test]` cria um banco temporário próprio.
- **Lint**: `cargo clippy --all-targets` e `cargo fmt`, com largura de 120 definida em `rustfmt.toml`.
- **WASM das regras**: `cd web && npm run rules`. Rode depois de qualquer mudança em `rust/rules`.
  - **Atenção:** a pasta `rust/rules` sumiu em 13/11/2026 e saiu do workspace.
    Enquanto ela não voltar, o site usa o WASM já gerado em `web/src/lib/rules/pkg`, que agora fica no git, e `npm run rules` não funciona.
  O resultado vai para `web/src/lib/rules/pkg`, que é gerado e fica fora do git.
- **Site**:
  - `cd web && npm test` roda o Vitest. Os testes carregam o WASM real e rodam também os fixtures.
  - `npm run check` roda o svelte-check e precisa terminar com 0 erros.
  - `npm run build` gera o site.
- **Rodar tudo localmente**:
  1. `cd rust && ALLOW_DEV_LOGIN=true cargo run -p myapp-backend` sobe o backend na porta 8080.
  2. `cd web && npm run dev` sobe o site na porta 5173. O Vite repassa `/v1` e `/health` para o backend.
- **Servidor único**, como em produção:
  1. `cd web && npm run build`.
  2. `cd rust && STATIC_DIR=../web/dist cargo run -p myapp-backend` serve o site e a API juntos na porta 8080.

## Publicar (Railway)

- `Dockerfile` na raiz gera uma imagem só: compila o site, compila o backend e serve os dois na mesma porta.
  `railway.json` aponta para ele e usa `/health` como verificação.
- Testar a imagem localmente: `docker build -t myapp:local .` (o Docker fica em `/Applications/Docker.app/Contents/Resources/bin`).
- No Railway:
  1. Criar um projeto com um banco PostgreSQL e um serviço a partir do repositório (ou `railway up`).
  2. Variáveis do serviço:
     - `DATABASE_URL=${{Postgres.DATABASE_URL}}`
     - `CLIENT_IP_HEADER=x-real-ip`
     - Não defina `ALLOW_DEV_LOGIN` em produção.
     - O Railway define `PORT` sozinho.
  3. Gerar um domínio em Settings → Networking.
- As migrações rodam sozinhas ao iniciar.
- Publicado no projeto `charismatic-essence`, serviço `funnycoins`: https://funnycoins-production.up.railway.app
  - Para publicar de novo: `railway up --service funnycoins --ci`.
  - Sem git, o `railway up` ignora o `.gitignore` e o `.dockerignore`. Ele usa o `.railwayignore`.
    Sem esse arquivo, o envio passa de 1 GB, por causa de `rust/target`, e falha.

## Arquitetura

```
MyApp/
  Models/
    FinanceModels.swift   modelos SwiftData, enums, BRFormat
    GameEngine.swift      GameSnapshot: níveis, fluxo, XP, patentes, conquistas
    PetEngine.swift       bichinho: necessidades, humor, evolução, falas
    SyncModels.swift      contrato da API: registros, centavos, conversão de modelos
    SyncEngine.swift      motor de sincronização e correção de identificadores
  Views/
    PetHomeView.swift     aba do bichinho (primeira aba)
    PetView.swift         desenho e animações do bichinho
    JourneyView.swift     slides: Nível 1, Nível 2, Conquistas
    GainWizardView.swift  passo a passo para registrar cada ganho
    CashFlowView.swift    entradas e saídas
    BillsView.swift       contas fixas mensais
    InvestmentsView.swift Nível 2: carteira e aportes
    Forms.swift           formulários de perfil, gasto, conta, reserva e investimento
    Components.swift      componentes reutilizáveis
    AppIconView.swift     arte do ícone do app
  Assets.xcassets/AppIcon.appiconset   PNG de 1024 para iOS e tamanhos do macOS
MyAppTests/               testes com Swift Testing
  Fixtures/rules-fixtures.json   casos das regras do jogo, compartilhados com o Rust
shared/API.md             contrato da API entre app, backend e site
rust/                     workspace Cargo
  rules/                  regras do jogo em Rust: mesma especificação de GameEngine e PetEngine
    src/game.rs           níveis, fluxo, XP, patentes, conquistas, GainPlan, situação das contas
    src/pet.rs            necessidades, humor, evolução e falas
    src/catalog.rs        valores crus dos enums e textos (categorias, modalidades, cores, dicas)
    src/wasm.rs           funções exportadas para o site (feature "wasm"), JSON de entrada e saída
    tests/fixtures.rs     lê rules-fixtures.json
  backend/                Axum + SQLx + PostgreSQL
    migrations/           esquema: users, identities, sessions, records
    src/sync.rs           POST /v1/sync
    src/auth.rs           login (código da conta, Apple, Google, dev), sessões, logout, exclusão de conta
    src/identity.rs       validação dos JWT da Apple e do Google
    tests/api.rs          testes da API contra o Postgres; keys/ tem a chave RSA só de teste
web/                      site em Svelte 5 + Vite + TypeScript
  src/lib/                lógica testável: store, sync, api, game (ponte WASM), actions, money, dates, pet
  src/components/         Pet (bichinho em SVG), Icon, CurrencyInput, Modal, Ring, Bar, StepDots
  src/views/              PetHome, Journey, CashFlow, Bills, Investments, Account
  src/forms/              ProfileForm, GainWizard, EntryForm, BillForm, ReserveForm, InvestmentForm
```

### Site: regras
- O site **não reimplementa regra do jogo**. Tudo vem do WASM de `rust/rules`, por `computeSnapshot` e `computeGainPlan` em `web/src/lib/game.ts`.
  Regra nova vai para o Rust e entra nos fixtures quando couber. A mesma regra também precisa entrar no Swift.
- Ações do jogador ficam em `web/src/lib/actions.ts`, fora das telas, e são testadas. Exemplos: salvar ganho, pagar conta, depositar.
- Dinheiro é `number` inteiro em centavos. Para exibir, use `brl()`. Para digitar, use `CurrencyInput`, que lê com `centsFromTyping`.
- Os dados ficam no `localStorage` no formato `SyncRecord` da API.
  - `RecordStore` segue as mesmas regras do app: `update` avança `updatedAt`, `softDelete` só marca, e as telas usam `active()`.
  - O perfil usado é o mais antigo.
- O site funciona sem login. Com login, sincroniza 1,5 s depois de cada alteração, a cada minuto e ao voltar o foco.
- **Login principal: código da conta.**
  - `POST /v1/auth/code/new` cria a conta e devolve um código como `K7QM-4XPA-9RTD`.
    São 12 caracteres de um alfabeto sem letras que se confundem (`23456789ABCDEFGHJKMNPQRSTWXYZ`).
  - `POST /v1/auth/code` entra com o código. Aceita minúsculas, espaços e hífens.
  - O servidor guarda só o hash SHA-256, em `identities` com `provider = 'code'`. Quem perder o código perde o acesso.
  - O site guarda o código junto da sessão, no `localStorage`, para mostrá-lo na aba Conta.
  - O formato fica em `web/src/lib/accountCode.ts` e precisa ser igual ao de `rust/backend/src/auth.rs`.
- **Ícones do site**: SVG de traço fino com `currentColor`, por `<Icon name=... />`. Os desenhos ficam em `web/src/lib/icons.ts`, baseados no Lucide.
  Não use emojis na interface.
- Sair da conta mantém os dados no navegador. Excluir a conta apaga os dados no servidor e no navegador.
- O desenho do bichinho em `Pet.svelte` reproduz `PetView.swift` com as mesmas frações. As formas ficam em `web/src/lib/pet.ts`.
  Ao mudar a arte no app, mude no site também. O Filhote continua intocável.
- Variáveis do site:
  - `VITE_API_URL` aponta para o backend. Vazio usa o proxy do Vite.
  - `VITE_GOOGLE_CLIENT_ID` liga o botão do Google.
  - `VITE_DEV_LOGIN=true` mostra o login só pelo nome fora do modo dev.
- Variáveis do backend: `DATABASE_URL`, `BIND` (ou só `PORT`), `APPLE_CLIENT_IDS`, `GOOGLE_CLIENT_IDS`, `ALLOW_DEV_LOGIN`,
  `CORS_ORIGINS`, `STATIC_DIR` e `CLIENT_IP_HEADER`.
- **Limite de tentativas**, por IP e em memória (`rust/backend/src/limit.rs`):
  - criar conta: 10 por hora;
  - entrar com código: 30 a cada 15 minutos.
  - Atrás de um proxy, defina `CLIENT_IP_HEADER` (no Railway, `x-real-ip`). Sem isso, todos parecem vir do IP do proxy.
- Com `STATIC_DIR` apontando para `web/dist`, o backend também serve o site, na mesma porta e na mesma origem, sem CORS.
  - Caminhos que não são arquivos devolvem o `index.html`. Rotas desconhecidas em `/v1` respondem 404 em JSON.
  - Sem `STATIC_DIR`, o backend serve só a API.
  - Para atualizar o site, basta rodar `npm run build` de novo, sem recompilar o Rust.

### Sincronização (app + backend + site)
- **Plano:**
  1. Modelos prontos para sincronizar. **Feito.**
  2. Backend em Rust: Axum, SQLx e PostgreSQL. **Feito**, em `rust/backend`.
     Login por código da conta pronto. Login com Apple e Google pronto, mas sem client IDs configurados ainda.
  3. App conectado: login e sincronização. **Parcial:** contrato e motor prontos e testados. Faltam o cliente HTTP, o login e a tela.
  4. Site em Svelte, com as regras em Rust compiladas para WebAssembly e o bichinho em SVG. **Feito**, em `web/`.
     Hoje usa login por código da conta, e também Google ou login de desenvolvimento quando configurados. Hospedagem preparada para o Railway.
- Todo modelo SwiftData tem `syncID`, `updatedAt` e `deletedAt`.
  - **Ao editar** um registro existente, chame `touch()`.
  - **Para excluir**, use `softDelete()`. Nunca use `context.delete`.
  - **Telas e jogo** usam os filtros `.active`, que escondem os excluídos.
- Conflitos: vence o `updatedAt` mais recente. Em empate, fica a versão local.
- Datas trafegam em milissegundos. `syncPrecision` trunca para evitar diferenças falsas.
- Dinheiro trafega em centavos (`Decimal.cents` e `Decimal(cents:)`).
- `SyncMaintenance.repairDuplicateIDs` roda ao abrir o app. Ele corrige UUIDs repetidos deixados pela migração de dados antigos.
- Toda mudança nas regras do jogo precisa atualizar `rules-fixtures.json`.
  Os testes em Swift, em Rust (`rust/rules`) e do site (pelo WASM) leem esse arquivo.

### Ícone do app
- O ícone mostra o Filhote verde sobre fundo dourado, com uma moeda de "R$". A fonte é `AppIconView`.
- Ao mudar a arte, gere o PNG de novo. Para isso, renderize `AppIconView(size: 1024)` com `ImageRenderer`, na escala 1 e opaco.
  Depois substitua `AppIcon-1024.png` e gere os tamanhos do macOS com `sips -z`.
- O PNG não pode ter transparência.
- O target usa `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
  A ferramenta de build settings não aceita esse nome, então ele foi definido direto no projeto.
- visionOS ainda não tem ícone próprio, porque exige um ícone em camadas.

- `GameSnapshot` é calculado a cada renderização a partir das consultas do SwiftData em `MainTabView`.
  XP, conquistas e humor **não são salvos**: são derivados dos dados. Isso mantém tudo consistente.
- `GameSnapshot` recebe `now`, o que permite testar regras que dependem de data.
- Enums são salvos como `String` cru (`kindRaw`, `modalityRaw`...). Nunca renomeie um raw value existente.
- Campos novos em modelos SwiftData precisam de valor padrão para a migração automática funcionar.

## Regras do jogo (especificação atual)

### Nível 1: reserva de emergência
- Meta = custo de vida mensal × meses escolhidos. O padrão é 6, e o intervalo vai de 3 a 24.
- Depósitos e retiradas são `ReserveMovement`, com valor positivo ou negativo.
- Concluído quando saldo ≥ meta. Isso libera o Nível 2.

### Nível 2: investimentos
- Bloqueado até concluir o Nível 1.
- Meta mensal = `investPercent`% das entradas do mês. O padrão é 10%.
- Modalidades: Tesouro Selic, CDB, LCI/LCA, Tesouro IPCA+, FII, Ações, ETFs, Cripto, Previdência,
  **Cursos e educação** e Outros.
- Cursos e educação contam como investimento em você: risco 0, rótulo "Investimento em você".
  Contam para a diversificação.

### Registro de ganho (passo a passo)
Origem → valor → quanto separar → comemoração.
- No Nível 1, a parte separada vai para a reserva, limitada ao que falta para completar.
- No Nível 2, vai para um investimento na modalidade escolhida.

### XP e patentes
| Ação | XP |
|---|---|
| Lançamento | 5 |
| Conta paga, por mês | 15 |
| Depósito na reserva | 20 |
| Aporte | 30 |
| Conquista desbloqueada | 100 |

Patentes: Aprendiz (0), Poupador (200), Estrategista (600), Investidor (1500), Mestre das Finanças (4000).

### Bichinho
- Necessidades de 0 a 1:
  - **Fome** cai 20% por dia sem lançamentos.
  - **Proteção** acompanha a reserva.
  - **Alegria** começa em 0,5. Perde 0,25 por conta atrasada. Ganha 0,25 com todas as contas pagas e 0,25 se guardou ou investiu no mês.
- Humor, na ordem de prioridade: doente se houver conta atrasada, com fome se a fome estiver abaixo de 0,3. Pela média: feliz a partir de 0,7, tranquilo a partir de 0,4, senão triste.
- Evolução: Ovo, sem lançamentos → Filhote → Jovem, com 50% da reserva → Adulto, com o Nível 1 completo
  → Lendário, com o Nível 1 completo mais 3 modalidades ou 1500 XP.
- Formas: cada estágio tem uma forma própria, definida em `PetStage.appearance` e desenhada por `PetView`.
  Cada evolução ganha mais partes que a anterior. Isso é testado.

  | Estágio | Forma |
  |---|---|
  | Ovo | Ovo pintado que balança, com 7 espinhos simétricos e nenhum embaixo. Ver `EggDesign`. |
  | Filhote | Bolinha redonda sem partes extras. **Aprovada pelo usuário: não alterar.** |
  | Jovem | Mais alto, orelhinhas pontudas, bracinhos (um acena) e broto de folha |
  | Adulto | Orelhas longas, rabinho enrolado e escudo na barriga, pela reserva completa |
  | Lendário | Asas que batem, aura dourada com faíscas, coroa e estrela na barriga |

## Decisões em aberto

Itens para especificar melhor antes de implementar:
- Compra de curso **antes** de completar a reserva: hoje só dá para registrar como gasto da categoria Educação, porque o Nível 2 está bloqueado. Deveria ser liberado como exceção?
- Investimentos guardam só o valor aportado. Falta acompanhar o valor atual e o rendimento.
- Existe um Nível 3? Por exemplo, diversificação ou independência financeira.
- Contas fixas: permitir desfazer pagamento e escolher a data real do pagamento.
- Notificações: o bichinho avisar quando estiver com fome ou quando uma conta vencer.
- Datas ainda usam o formato do aparelho em alguns textos. Avaliar se devem ser fixadas em pt-BR.
- Dois aparelhos que fizerem o cadastro inicial antes de sincronizar vão criar dois perfis. Hoje o app usa o mais antigo. Definir se os perfis devem ser mesclados.
- Client IDs da Apple (Services ID para o site) e do Google.
- Login com Apple no site: o backend já aceita o token, mas o site ainda não tem o botão.
