use std::net::SocketAddr;
use std::sync::Arc;

use myapp_backend::identity::Provider;
use myapp_backend::limit::Limits;
use myapp_backend::{AppState, Config, app};
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,tower_http=info".into()))
        .init();

    let config = Config::from_env();
    let db = PgPoolOptions::new().max_connections(10).connect(&config.database_url).await?;
    sqlx::migrate!("./migrations").run(&db).await?;

    let state = AppState {
        db,
        http: reqwest::Client::builder().timeout(std::time::Duration::from_secs(10)).build()?,
        apple: Arc::new(Provider::apple(config.apple_client_ids.clone())),
        google: Arc::new(Provider::google(config.google_client_ids.clone())),
        allow_dev_login: config.allow_dev_login,
        limits: Arc::new(Limits::default()),
        client_ip_header: config.client_ip_header.clone(),
    };
    if state.allow_dev_login {
        tracing::warn!("login de desenvolvimento ligado: não use em produção");
    }

    let static_dir = config.static_dir.as_deref();
    match static_dir {
        Some(dir) if !dir.join("index.html").is_file() => {
            tracing::warn!("STATIC_DIR={} não tem index.html: rode `npm run build` em web/", dir.display())
        }
        Some(dir) => tracing::info!("servindo o site de {}", dir.display()),
        None => tracing::info!("STATIC_DIR vazio: servindo só a API"),
    }

    let listener = tokio::net::TcpListener::bind(&config.bind).await?;
    tracing::info!("ouvindo em http://{}", listener.local_addr()?);
    let service = app(state, &config.cors_origins, static_dir).into_make_service_with_connect_info::<SocketAddr>();
    axum::serve(listener, service).await?;
    Ok(())
}
