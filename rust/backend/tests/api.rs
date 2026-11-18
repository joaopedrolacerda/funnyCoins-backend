//! Testes da API contra um PostgreSQL de verdade.
//! Cada teste roda num banco temporário criado pelo `sqlx::test` a partir de `DATABASE_URL`.

use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use jsonwebtoken::{Algorithm, EncodingKey, Header, encode};
use myapp_backend::identity::{KeySource, Provider};
use myapp_backend::limit::Limits;
use myapp_backend::{AppState, app};
use serde_json::{Value, json};
use sqlx::PgPool;
use tower::ServiceExt;

const GOOGLE_CLIENT: &str = "site-teste.apps.googleusercontent.com";

fn test_app(db: PgPool, allow_dev_login: bool) -> Router {
    app(test_state(db, allow_dev_login), &[], None)
}

fn test_state(db: PgPool, allow_dev_login: bool) -> AppState {
    let keys: jsonwebtoken::jwk::JwkSet = serde_json::from_str(include_str!("keys/test-jwks.json")).unwrap();
    let google = Provider {
        name: "google",
        issuers: vec!["https://accounts.google.com".into()],
        audiences: vec![GOOGLE_CLIENT.into()],
        keys: KeySource::Static(keys),
    };
    AppState {
        db,
        http: reqwest::Client::new(),
        apple: Arc::new(Provider::apple(vec![])),
        google: Arc::new(google),
        allow_dev_login,
        limits: Arc::new(Limits::default()),
        client_ip_header: Some("x-real-ip".into()),
    }
}

async fn call(app: &Router, method: &str, path: &str, token: Option<&str>, body: Option<Value>) -> (StatusCode, Value) {
    let mut request = Request::builder().method(method).uri(path);
    if let Some(token) = token {
        request = request.header("authorization", format!("Bearer {token}"));
    }
    let body = match body {
        Some(value) => {
            request = request.header("content-type", "application/json");
            Body::from(value.to_string())
        }
        None => Body::empty(),
    };
    let response = app.clone().oneshot(request.body(body).unwrap()).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let value = if bytes.is_empty() { Value::Null } else { serde_json::from_slice(&bytes).unwrap() };
    (status, value)
}

async fn login(app: &Router, name: &str) -> String {
    let (status, body) = call(app, "POST", "/v1/auth/dev", None, Some(json!({ "name": name }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["token"].as_str().unwrap().to_string()
}

fn entry(id: &str, title: &str, updated_at: i64) -> Value {
    json!({
        "id": id, "kind": "cashEntry", "updatedAt": updated_at,
        "data": { "title": title, "amountCents": 500000, "date": 1_800_000_000_000_i64, "kind": "income", "category": "salary" }
    })
}

async fn sync(app: &Router, token: &str, cursor: Value, changes: Vec<Value>) -> Value {
    let (status, body) =
        call(app, "POST", "/v1/sync", Some(token), Some(json!({ "cursor": cursor, "changes": changes }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body
}

const ID_A: &str = "6f1c4b8e-0000-4000-8000-00000000000a";
const ID_B: &str = "6f1c4b8e-0000-4000-8000-00000000000b";

#[sqlx::test(migrations = "./migrations")]
async fn health_responde_ok(db: PgPool) {
    let app = test_app(db, false);
    let (status, body) = call(&app, "GET", "/health", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, json!({ "status": "ok" }));
}

#[sqlx::test(migrations = "./migrations")]
async fn sync_exige_login(db: PgPool) {
    let app = test_app(db, true);
    let (status, _) = call(&app, "POST", "/v1/sync", None, Some(json!({ "cursor": null, "changes": [] }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) =
        call(&app, "POST", "/v1/sync", Some("inventado"), Some(json!({ "cursor": null, "changes": [] }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "./migrations")]
async fn login_de_desenvolvimento_so_quando_ligado(db: PgPool) {
    let app = test_app(db, false);
    let (status, _) = call(&app, "POST", "/v1/auth/dev", None, Some(json!({ "name": "ana" }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "./migrations")]
async fn mesmo_login_volta_para_o_mesmo_usuario(db: PgPool) {
    let app = test_app(db, true);
    let (_, first) = call(&app, "POST", "/v1/auth/dev", None, Some(json!({ "name": "ana" }))).await;
    let (_, second) = call(&app, "POST", "/v1/auth/dev", None, Some(json!({ "name": "ana" }))).await;
    assert_eq!(first["userId"], second["userId"]);
    assert_ne!(first["token"], second["token"]);
}

#[sqlx::test(migrations = "./migrations")]
async fn primeira_sync_devolve_o_que_chegou_e_o_cursor(db: PgPool) {
    let app = test_app(db, true);
    let token = login(&app, "ana").await;

    let body = sync(&app, &token, Value::Null, vec![entry(ID_A, "Salário", 10), entry(ID_B, "Freela", 10)]).await;
    assert_eq!(body["cursor"], 2);
    assert_eq!(body["changes"].as_array().unwrap().len(), 2);
    assert_eq!(body["changes"][0]["data"]["title"], "Salário");
    assert!(body["changes"][0].get("deletedAt").is_none(), "ativo não manda deletedAt");

    // Nada novo depois do cursor.
    let body = sync(&app, &token, json!(2), vec![]).await;
    assert_eq!(body["cursor"], 2);
    assert_eq!(body["changes"], json!([]));
}

#[sqlx::test(migrations = "./migrations")]
async fn vence_o_updated_at_mais_recente_e_empate_mantem_o_salvo(db: PgPool) {
    let app = test_app(db, true);
    let token = login(&app, "ana").await;
    sync(&app, &token, Value::Null, vec![entry(ID_A, "Original", 100)]).await;

    // Mais antigo: ignorado. Empate: ignorado.
    let body = sync(&app, &token, json!(1), vec![entry(ID_A, "Antigo", 50), entry(ID_A, "Empate", 100)]).await;
    assert_eq!(body["cursor"], 1);
    assert_eq!(body["changes"], json!([]));

    // Mais novo: grava e volta na resposta.
    let body = sync(&app, &token, json!(1), vec![entry(ID_A, "Novo", 200)]).await;
    assert_eq!(body["cursor"], 2);
    assert_eq!(body["changes"][0]["data"]["title"], "Novo");

    let all = sync(&app, &token, Value::Null, vec![]).await;
    assert_eq!(all["changes"].as_array().unwrap().len(), 1, "o id é o mesmo: não duplica");
}

#[sqlx::test(migrations = "./migrations")]
async fn exclusao_viaja_como_deleted_at(db: PgPool) {
    let app = test_app(db, true);
    let token = login(&app, "ana").await;
    sync(&app, &token, Value::Null, vec![entry(ID_A, "Salário", 100)]).await;

    let mut deleted = entry(ID_A, "Salário", 200);
    deleted["deletedAt"] = json!(200);
    let body = sync(&app, &token, json!(1), vec![deleted]).await;
    assert_eq!(body["changes"][0]["deletedAt"], 200);
}

#[sqlx::test(migrations = "./migrations")]
async fn outro_aparelho_recebe_as_alteracoes(db: PgPool) {
    let app = test_app(db, true);
    let phone = login(&app, "ana").await;
    let laptop = login(&app, "ana").await;

    let first = sync(&app, &laptop, Value::Null, vec![]).await;
    assert_eq!(first["cursor"], 0);

    sync(&app, &phone, Value::Null, vec![entry(ID_A, "Do celular", 10)]).await;
    let body = sync(&app, &laptop, first["cursor"].clone(), vec![]).await;
    assert_eq!(body["changes"][0]["data"]["title"], "Do celular");
}

#[sqlx::test(migrations = "./migrations")]
async fn usuarios_nao_veem_registros_um_do_outro(db: PgPool) {
    let app = test_app(db, true);
    let ana = login(&app, "ana").await;
    let bia = login(&app, "bia").await;

    sync(&app, &ana, Value::Null, vec![entry(ID_A, "Da Ana", 10)]).await;
    // Mesmo id em outra conta é outro registro.
    let body = sync(&app, &bia, Value::Null, vec![entry(ID_A, "Da Bia", 5)]).await;
    assert_eq!(body["changes"].as_array().unwrap().len(), 1);
    assert_eq!(body["changes"][0]["data"]["title"], "Da Bia");

    let body = sync(&app, &ana, Value::Null, vec![]).await;
    assert_eq!(body["changes"][0]["data"]["title"], "Da Ana");
}

#[sqlx::test(migrations = "./migrations")]
async fn cursor_maior_que_o_do_servidor_manda_tudo(db: PgPool) {
    let app = test_app(db, true);
    let token = login(&app, "ana").await;
    sync(&app, &token, Value::Null, vec![entry(ID_A, "Salário", 10)]).await;
    let body = sync(&app, &token, json!(999), vec![]).await;
    assert_eq!(body["cursor"], 1);
    assert_eq!(body["changes"].as_array().unwrap().len(), 1);
}

#[sqlx::test(migrations = "./migrations")]
async fn recusa_registro_fora_do_contrato(db: PgPool) {
    let app = test_app(db, true);
    let token = login(&app, "ana").await;
    let invalid = json!({ "id": ID_A, "kind": "cashEntry", "updatedAt": 1, "data": { "title": "x" } });
    let (status, body) =
        call(&app, "POST", "/v1/sync", Some(&token), Some(json!({ "cursor": null, "changes": [invalid] }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("amountCents"));

    // Nada foi gravado.
    let body = sync(&app, &token, Value::Null, vec![]).await;
    assert_eq!(body["changes"], json!([]));
}

#[sqlx::test(migrations = "./migrations")]
async fn excluir_conta_apaga_tudo(db: PgPool) {
    let app = test_app(db.clone(), true);
    let token = login(&app, "ana").await;
    sync(&app, &token, Value::Null, vec![entry(ID_A, "Salário", 10)]).await;

    let (status, _) = call(&app, "DELETE", "/v1/account", Some(&token), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, _) =
        call(&app, "POST", "/v1/sync", Some(&token), Some(json!({ "cursor": null, "changes": [] }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "a sessão foi junto");
    let records: i64 = sqlx::query_scalar("SELECT count(*) FROM records").fetch_one(&db).await.unwrap();
    assert_eq!(records, 0);

    // Um novo login com o mesmo nome começa do zero.
    let token = login(&app, "ana").await;
    let body = sync(&app, &token, Value::Null, vec![]).await;
    assert_eq!(body["changes"], json!([]));
}

#[sqlx::test(migrations = "./migrations")]
async fn logout_encerra_a_sessao(db: PgPool) {
    let app = test_app(db, true);
    let token = login(&app, "ana").await;
    let (status, _) = call(&app, "POST", "/v1/auth/logout", Some(&token), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) =
        call(&app, "POST", "/v1/sync", Some(&token), Some(json!({ "cursor": null, "changes": [] }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

// Login com Google: token assinado pela chave de teste.

fn google_token(audience: &str, expires_in: i64) -> String {
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64;
    let claims = json!({
        "iss": "https://accounts.google.com", "aud": audience, "sub": "google-123",
        "iat": now, "exp": now + expires_in
    });
    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some("test-key".into());
    let key = EncodingKey::from_rsa_pem(include_bytes!("keys/test-private.pem")).unwrap();
    encode(&header, &claims, &key).unwrap()
}

#[sqlx::test(migrations = "./migrations")]
async fn login_com_google_valida_o_token(db: PgPool) {
    let app = test_app(db, false);

    let (status, body) =
        call(&app, "POST", "/v1/auth/google", None, Some(json!({ "identityToken": google_token(GOOGLE_CLIENT, 600) })))
            .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let token = body["token"].as_str().unwrap();
    sync(&app, token, Value::Null, vec![]).await;

    let (status, _) =
        call(&app, "POST", "/v1/auth/google", None, Some(json!({ "identityToken": google_token("outro-app", 600) })))
            .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "audience errada");

    let (status, _) = call(
        &app,
        "POST",
        "/v1/auth/google",
        None,
        Some(json!({ "identityToken": google_token(GOOGLE_CLIENT, -600) })),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "token vencido");

    let (status, _) = call(&app, "POST", "/v1/auth/google", None, Some(json!({ "identityToken": "lixo" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "./migrations")]
async fn login_com_apple_sem_configuracao_responde_404(db: PgPool) {
    let app = test_app(db, false);
    let (status, _) = call(&app, "POST", "/v1/auth/apple", None, Some(json!({ "identityToken": "x" }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

/// Cria uma pasta temporária com um site mínimo, no formato de `npm run build`.
fn fake_site() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("myapp-site-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(dir.join("assets")).unwrap();
    std::fs::write(dir.join("index.html"), "<!doctype html><title>MyApp</title>").unwrap();
    std::fs::write(dir.join("assets/app.js"), "console.log('oi')").unwrap();
    dir
}

async fn get_text(app: &Router, path: &str) -> (StatusCode, String, String) {
    let request = Request::builder().uri(path).body(Body::empty()).unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let content_type =
        response.headers().get("content-type").and_then(|value| value.to_str().ok()).unwrap_or_default().to_string();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, content_type, String::from_utf8_lossy(&bytes).into_owned())
}

#[sqlx::test(migrations = "./migrations")]
async fn serve_o_site_na_mesma_porta_da_api(db: PgPool) {
    let dir = fake_site();
    let app = app(test_state(db, true), &[], Some(&dir));

    let (status, content_type, body) = get_text(&app, "/").await;
    assert_eq!(status, StatusCode::OK);
    assert!(content_type.starts_with("text/html"), "{content_type}");
    assert!(body.contains("<title>MyApp</title>"));

    let (status, content_type, body) = get_text(&app, "/assets/app.js").await;
    assert_eq!(status, StatusCode::OK);
    assert!(content_type.contains("javascript"), "{content_type}");
    assert_eq!(body, "console.log('oi')");

    // A API continua funcionando ao lado do site.
    let (status, body) = call(&app, "GET", "/health", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, json!({ "status": "ok" }));
    login(&app, "ana").await;

    std::fs::remove_dir_all(dir).unwrap();
}

#[sqlx::test(migrations = "./migrations")]
async fn caminho_desconhecido_do_site_devolve_o_index(db: PgPool) {
    let dir = fake_site();
    let app = app(test_state(db, false), &[], Some(&dir));

    let (status, _, body) = get_text(&app, "/qualquer/tela").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("<title>MyApp</title>"));

    std::fs::remove_dir_all(dir).unwrap();
}

#[sqlx::test(migrations = "./migrations")]
async fn rota_desconhecida_da_api_responde_404_em_json(db: PgPool) {
    let dir = fake_site();
    let with_site = app(test_state(db.clone(), false), &[], Some(&dir));
    let api_only = test_app(db, false);

    for app in [&with_site, &api_only] {
        let (status, body) = call(app, "GET", "/v1/inexistente", None, None).await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        assert_eq!(body, json!({ "error": "rota não encontrada" }));
    }

    std::fs::remove_dir_all(dir).unwrap();
}

#[sqlx::test(migrations = "./migrations")]
async fn sem_static_dir_nao_serve_site(db: PgPool) {
    let app = test_app(db, false);
    let (status, _, _) = get_text(&app, "/").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

async fn new_code_account(app: &Router) -> Value {
    let (status, body) = call(app, "POST", "/v1/auth/code/new", None, None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body
}

#[sqlx::test(migrations = "./migrations")]
async fn conta_nova_devolve_codigo_e_sessao(db: PgPool) {
    let app = test_app(db.clone(), false);
    let account = new_code_account(&app).await;
    let code = account["code"].as_str().unwrap();
    assert_eq!(code.len(), 14, "{code}");
    let token = account["token"].as_str().unwrap();
    sync(&app, token, Value::Null, vec![]).await;

    // O código não fica salvo em texto no banco.
    let subjects: Vec<String> = sqlx::query_scalar("SELECT subject FROM identities").fetch_all(&db).await.unwrap();
    assert_eq!(subjects.len(), 1);
    assert!(!subjects[0].contains(&code.replace('-', "")));
}

#[sqlx::test(migrations = "./migrations")]
async fn codigo_entra_na_mesma_conta_em_outro_aparelho(db: PgPool) {
    let app = test_app(db, false);
    let account = new_code_account(&app).await;
    let first_token = account["token"].as_str().unwrap();
    sync(&app, first_token, Value::Null, vec![entry(ID_A, "Salário", 1000)]).await;

    // Digitado em minúsculas e sem hífens, como alguém faria no celular.
    let typed = account["code"].as_str().unwrap().replace('-', " ").to_lowercase();
    let (status, login) = call(&app, "POST", "/v1/auth/code", None, Some(json!({ "code": typed }))).await;
    assert_eq!(status, StatusCode::OK, "{login}");
    assert_eq!(login["userId"], account["userId"]);
    assert_ne!(login["token"], account["token"]);

    let pulled = sync(&app, login["token"].as_str().unwrap(), Value::Null, vec![]).await;
    assert_eq!(pulled["changes"][0]["id"], ID_A);
}

#[sqlx::test(migrations = "./migrations")]
async fn cada_conta_nova_tem_seu_codigo(db: PgPool) {
    let app = test_app(db, false);
    let first = new_code_account(&app).await;
    let second = new_code_account(&app).await;
    assert_ne!(first["code"], second["code"]);
    assert_ne!(first["userId"], second["userId"]);
}

#[sqlx::test(migrations = "./migrations")]
async fn codigo_desconhecido_ou_mal_digitado_nao_entra(db: PgPool) {
    let app = test_app(db, false);
    new_code_account(&app).await;

    let (status, body) = call(&app, "POST", "/v1/auth/code", None, Some(json!({ "code": "2222-2222-2222" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body, json!({ "error": "código não encontrado: confira se digitou certo" }));

    let (status, _) = call(&app, "POST", "/v1/auth/code", None, Some(json!({ "code": "curto" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[sqlx::test(migrations = "./migrations")]
async fn excluir_conta_invalida_o_codigo(db: PgPool) {
    let app = test_app(db, false);
    let account = new_code_account(&app).await;
    let (status, _) = call(&app, "DELETE", "/v1/account", account["token"].as_str(), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, _) = call(&app, "POST", "/v1/auth/code", None, Some(json!({ "code": account["code"] }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

async fn post_from(app: &Router, path: &str, ip: &str, body: Value) -> StatusCode {
    let request = Request::builder()
        .method("POST")
        .uri(path)
        .header("content-type", "application/json")
        .header("x-real-ip", ip)
        .body(Body::from(body.to_string()))
        .unwrap();
    app.clone().oneshot(request).await.unwrap().status()
}

#[sqlx::test(migrations = "./migrations")]
async fn limita_criacao_de_contas_por_ip(db: PgPool) {
    let app = test_app(db, false);
    for _ in 0..10 {
        assert_eq!(post_from(&app, "/v1/auth/code/new", "203.0.113.7", json!({})).await, StatusCode::OK);
    }
    assert_eq!(post_from(&app, "/v1/auth/code/new", "203.0.113.7", json!({})).await, StatusCode::TOO_MANY_REQUESTS);
    // Outro endereço continua podendo criar.
    assert_eq!(post_from(&app, "/v1/auth/code/new", "203.0.113.8", json!({})).await, StatusCode::OK);
}

#[sqlx::test(migrations = "./migrations")]
async fn limita_tentativas_de_codigo_por_ip(db: PgPool) {
    let app = test_app(db, false);
    let wrong = json!({ "code": "2222-2222-2222" });
    for _ in 0..30 {
        assert_eq!(post_from(&app, "/v1/auth/code", "198.51.100.1", wrong.clone()).await, StatusCode::UNAUTHORIZED);
    }
    assert_eq!(post_from(&app, "/v1/auth/code", "198.51.100.1", wrong).await, StatusCode::TOO_MANY_REQUESTS);
}
