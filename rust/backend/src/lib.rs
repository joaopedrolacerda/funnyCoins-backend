//! Backend de sincronização do MyApp. Contrato em `shared/API.md`.

pub mod auth;
pub mod contract;
pub mod error;
pub mod identity;
pub mod limit;
pub mod sync;

use std::path::{Path, PathBuf};
use std::sync::Arc;

use axum::extract::DefaultBodyLimit;
use axum::http::{HeaderValue, Method, header};
use axum::routing::{any, delete, get, post};
use axum::{Json, Router};
use serde_json::{Value, json};
use sqlx::PgPool;
use tower_http::cors::CorsLayer;
use tower_http::services::{ServeDir, ServeFile};
use tower_http::trace::TraceLayer;

use crate::error::ApiError;
use crate::identity::Provider;
use crate::limit::Limits;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub http: reqwest::Client,
    pub apple: Arc<Provider>,
    pub google: Arc<Provider>,
    pub allow_dev_login: bool,
    pub limits: Arc<Limits>,
    /// Cabeçalho com o IP real quando há um proxy na frente. Vazio usa o IP da conexão.
    pub client_ip_header: Option<String>,
}

/// Configuração lida das variáveis de ambiente.
pub struct Config {
    pub database_url: String,
    pub bind: String,
    pub apple_client_ids: Vec<String>,
    pub google_client_ids: Vec<String>,
    pub allow_dev_login: bool,
    /// Sites autorizados a chamar a API pelo navegador. Vazio desliga o CORS.
    pub cors_origins: Vec<String>,
    /// Pasta do site gerado por `npm run build`. Vazio serve só a API.
    pub static_dir: Option<PathBuf>,
    pub client_ip_header: Option<String>,
}

fn list(name: &str) -> Vec<String> {
    std::env::var(name)
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(String::from)
        .collect()
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            database_url: std::env::var("DATABASE_URL").unwrap_or_else(|_| "postgres://myapp@localhost/myapp".into()),
            // Serviços como o Railway definem só a porta em PORT: aí escuta em todas as interfaces.
            bind: std::env::var("BIND")
                .ok()
                .or_else(|| std::env::var("PORT").ok().map(|port| format!("0.0.0.0:{port}")))
                .unwrap_or_else(|| "127.0.0.1:8080".into()),
            apple_client_ids: list("APPLE_CLIENT_IDS"),
            google_client_ids: list("GOOGLE_CLIENT_IDS"),
            allow_dev_login: std::env::var("ALLOW_DEV_LOGIN").is_ok_and(|value| value == "true"),
            cors_origins: list("CORS_ORIGINS"),
            static_dir: std::env::var("STATIC_DIR").ok().filter(|dir| !dir.is_empty()).map(PathBuf::from),
            client_ip_header: std::env::var("CLIENT_IP_HEADER").ok().filter(|name| !name.is_empty()),
        }
    }
}

async fn health() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

async fn api_not_found() -> ApiError {
    ApiError::NotFound("rota não encontrada".into())
}

/// Monta a API e, com `static_dir`, também o site na mesma porta.
/// Caminhos fora de `/v1` que não são arquivos devolvem o `index.html` do site.
/// Caminhos desconhecidos em `/v1` continuam respondendo 404 em JSON.
pub fn app(state: AppState, cors_origins: &[String], static_dir: Option<&Path>) -> Router {
    let mut router = Router::new()
        .route("/health", get(health))
        .route("/v1/auth/apple", post(auth::login_apple))
        .route("/v1/auth/google", post(auth::login_google))
        .route("/v1/auth/code", post(auth::login_code))
        .route("/v1/auth/code/new", post(auth::create_code_account))
        .route("/v1/auth/dev", post(auth::login_dev))
        .route("/v1/auth/logout", post(auth::logout))
        .route("/v1/sync", post(sync::sync))
        .route("/v1/account", delete(auth::delete_account))
        .route("/v1/{*rest}", any(api_not_found));
    if let Some(dir) = static_dir {
        router = router.fallback_service(ServeDir::new(dir).fallback(ServeFile::new(dir.join("index.html"))));
    }
    let router =
        router.layer(DefaultBodyLimit::max(10 * 1024 * 1024)).layer(TraceLayer::new_for_http()).with_state(state);

    let origins: Vec<HeaderValue> = cors_origins.iter().filter_map(|origin| origin.parse().ok()).collect();
    if origins.is_empty() {
        return router;
    }
    router.layer(
        CorsLayer::new()
            .allow_origin(origins)
            .allow_methods([Method::GET, Method::POST, Method::DELETE])
            .allow_headers([header::AUTHORIZATION, header::CONTENT_TYPE]),
    )
}
