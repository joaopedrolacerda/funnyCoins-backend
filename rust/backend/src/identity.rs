//! Validação dos tokens de login da Apple e do Google (JWT assinado com RS256).

use std::time::{Duration, Instant};

use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode, decode_header};
use serde::Deserialize;
use tokio::sync::RwLock;

use crate::error::ApiError;

/// Onde buscar as chaves públicas do provedor.
pub enum KeySource {
    /// Endereço JWKS do provedor. As chaves ficam em cache e são buscadas de novo quando aparece um `kid` novo.
    Remote { url: String, cache: RwLock<Option<(JwkSet, Instant)>> },
    /// Chaves fixas, usadas nos testes.
    Static(JwkSet),
}

impl KeySource {
    pub fn remote(url: &str) -> Self {
        Self::Remote { url: url.into(), cache: RwLock::new(None) }
    }
}

/// Provedor de login. Fica desligado quando não há nenhum client ID configurado.
pub struct Provider {
    pub name: &'static str,
    pub issuers: Vec<String>,
    pub audiences: Vec<String>,
    pub keys: KeySource,
}

#[derive(Deserialize)]
struct Claims {
    sub: String,
}

/// Intervalo mínimo entre duas buscas de chaves, para um token falso não forçar buscas sem parar.
const MIN_REFRESH: Duration = Duration::from_secs(60);

impl Provider {
    /// `audiences`: o bundle ID do app e o Services ID do site.
    pub fn apple(audiences: Vec<String>) -> Self {
        Self {
            name: "apple",
            issuers: vec!["https://appleid.apple.com".into()],
            audiences,
            keys: KeySource::remote("https://appleid.apple.com/auth/keys"),
        }
    }

    /// `audiences`: os client IDs OAuth do app e do site.
    pub fn google(audiences: Vec<String>) -> Self {
        Self {
            name: "google",
            issuers: vec!["https://accounts.google.com".into(), "accounts.google.com".into()],
            audiences,
            keys: KeySource::remote("https://www.googleapis.com/oauth2/v3/certs"),
        }
    }

    pub fn is_enabled(&self) -> bool {
        !self.audiences.is_empty()
    }

    /// Valida o token e devolve o identificador da pessoa no provedor (`sub`).
    pub async fn verify(&self, http: &reqwest::Client, token: &str) -> Result<String, ApiError> {
        let header = decode_header(token).map_err(|_| ApiError::InvalidIdentity)?;
        let kid = header.kid.ok_or(ApiError::InvalidIdentity)?;
        let key = self.decoding_key(http, &kid).await?;

        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_audience(&self.audiences);
        validation.set_issuer(&self.issuers);
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);

        let data = decode::<Claims>(token, &key, &validation).map_err(|_| ApiError::InvalidIdentity)?;
        Ok(data.claims.sub)
    }

    async fn decoding_key(&self, http: &reqwest::Client, kid: &str) -> Result<DecodingKey, ApiError> {
        let to_key = |set: &JwkSet| set.find(kid).and_then(|jwk| DecodingKey::from_jwk(jwk).ok());

        match &self.keys {
            KeySource::Static(set) => to_key(set).ok_or(ApiError::InvalidIdentity),
            KeySource::Remote { url, cache } => {
                if let Some((set, fetched_at)) = cache.read().await.as_ref() {
                    if let Some(key) = to_key(set) {
                        return Ok(key);
                    }
                    if fetched_at.elapsed() < MIN_REFRESH {
                        return Err(ApiError::InvalidIdentity);
                    }
                }
                let set: JwkSet = http
                    .get(url)
                    .send()
                    .await
                    .and_then(|response| response.error_for_status())
                    .map_err(ApiError::internal)?
                    .json()
                    .await
                    .map_err(ApiError::internal)?;
                let key = to_key(&set);
                *cache.write().await = Some((set, Instant::now()));
                key.ok_or(ApiError::InvalidIdentity)
            }
        }
    }
}
