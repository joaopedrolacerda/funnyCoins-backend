//! Login, sessões e exclusão de conta.

use axum::Json;
use axum::extract::{FromRequestParts, State};
use axum::http::StatusCode;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::AppState;
use crate::error::ApiError;
use crate::identity::Provider;
use crate::limit::ClientIp;

/// Duração de uma sessão.
const SESSION_DAYS: i32 = 180;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IdentityRequest {
    pub identity_token: String,
}

#[derive(Deserialize)]
pub struct CodeLoginRequest {
    pub code: String,
}

/// Resposta de uma conta nova: além da sessão, o código que a pessoa precisa guardar.
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NewAccountResponse {
    pub token: String,
    pub user_id: Uuid,
    pub code: String,
}

#[derive(Deserialize)]
pub struct DevLoginRequest {
    pub name: String,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginResponse {
    pub token: String,
    pub user_id: Uuid,
}

fn hash_token(token: &str) -> Vec<u8> {
    Sha256::digest(token.as_bytes()).to_vec()
}

/// Letras e números do código da conta, sem os que se confundem (0 e O, 1, I e L, U e V).
const CODE_ALPHABET: &[u8] = b"23456789ABCDEFGHJKMNPQRSTWXYZ";
/// 12 caracteres de 29 possíveis dão cerca de 58 bits.
const CODE_LEN: usize = 12;

/// Gera um código como `K7QM-4XPA-9RTD`.
fn new_account_code() -> Result<String, ApiError> {
    // Descarta os bytes acima do maior múltiplo do alfabeto para não favorecer nenhuma letra.
    let limit = (256 / CODE_ALPHABET.len() * CODE_ALPHABET.len()) as u8;
    let mut chars = Vec::with_capacity(CODE_LEN);
    while chars.len() < CODE_LEN {
        let mut bytes = [0u8; 32];
        getrandom::fill(&mut bytes).map_err(ApiError::internal)?;
        chars.extend(
            bytes.iter().filter(|&&byte| byte < limit).map(|&byte| CODE_ALPHABET[byte as usize % CODE_ALPHABET.len()]),
        );
    }
    let groups: Vec<String> =
        chars[..CODE_LEN].chunks(4).map(|group| String::from_utf8_lossy(group).into_owned()).collect();
    Ok(groups.join("-"))
}

/// Deixa o código como foi gerado, sem hífens nem espaços e em maiúsculas.
/// Devolve `None` quando o texto não tem o formato de um código.
pub fn normalize_code(input: &str) -> Option<String> {
    let code: String =
        input.chars().filter(|c| !c.is_whitespace() && *c != '-').map(|c| c.to_ascii_uppercase()).collect();
    (code.len() == CODE_LEN && code.bytes().all(|byte| CODE_ALPHABET.contains(&byte))).then_some(code)
}

/// O código não fica salvo: na tabela `identities` vai só o hash SHA-256 dele.
fn code_subject(normalized: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(normalized.as_bytes()))
}

/// Acha o usuário dessa conta de login ou cria um novo.
async fn find_or_create_user(state: &AppState, provider: &str, subject: &str) -> Result<Uuid, ApiError> {
    let mut tx = state.db.begin().await?;
    let new_id = Uuid::new_v4();
    sqlx::query("INSERT INTO users (id) VALUES ($1)").bind(new_id).execute(&mut *tx).await?;
    // Se a conta já existir, a inserção não faz nada e o usuário criado acima é descartado no rollback.
    let inserted =
        sqlx::query("INSERT INTO identities (provider, subject, user_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING")
            .bind(provider)
            .bind(subject)
            .bind(new_id)
            .execute(&mut *tx)
            .await?
            .rows_affected();

    if inserted == 1 {
        tx.commit().await?;
        return Ok(new_id);
    }
    tx.rollback().await?;
    let existing = sqlx::query_scalar("SELECT user_id FROM identities WHERE provider = $1 AND subject = $2")
        .bind(provider)
        .bind(subject)
        .fetch_one(&state.db)
        .await?;
    Ok(existing)
}

async fn create_session(state: &AppState, user_id: Uuid) -> Result<LoginResponse, ApiError> {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).map_err(ApiError::internal)?;
    let token = URL_SAFE_NO_PAD.encode(bytes);
    sqlx::query(
        "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES ($1, $2, now() + make_interval(days => $3))",
    )
    .bind(hash_token(&token))
    .bind(user_id)
    .bind(SESSION_DAYS)
    .execute(&state.db)
    .await?;
    Ok(LoginResponse { token, user_id })
}

async fn login_with(state: &AppState, provider: &Provider, identity_token: &str) -> Result<LoginResponse, ApiError> {
    if !provider.is_enabled() {
        return Err(ApiError::NotFound(format!("login com {} não está configurado", provider.name)));
    }
    let subject = provider.verify(&state.http, identity_token).await?;
    let user_id = find_or_create_user(state, provider.name, &subject).await?;
    create_session(state, user_id).await
}

pub async fn login_apple(
    State(state): State<AppState>,
    Json(body): Json<IdentityRequest>,
) -> Result<Json<LoginResponse>, ApiError> {
    login_with(&state, &state.apple, &body.identity_token).await.map(Json)
}

pub async fn login_google(
    State(state): State<AppState>,
    Json(body): Json<IdentityRequest>,
) -> Result<Json<LoginResponse>, ApiError> {
    login_with(&state, &state.google, &body.identity_token).await.map(Json)
}

/// Cria uma conta nova e devolve o código para entrar nela em outros aparelhos.
pub async fn create_code_account(
    State(state): State<AppState>,
    ClientIp(ip): ClientIp,
) -> Result<Json<NewAccountResponse>, ApiError> {
    state.limits.new_account.check(ip)?;
    let code = new_account_code()?;
    let subject = code_subject(&normalize_code(&code).ok_or_else(|| ApiError::internal("código gerado inválido"))?);
    let user_id = Uuid::new_v4();
    let mut tx = state.db.begin().await?;
    sqlx::query("INSERT INTO users (id) VALUES ($1)").bind(user_id).execute(&mut *tx).await?;
    // Sem ON CONFLICT: um código repetido nunca pode levar para a conta de outra pessoa.
    sqlx::query("INSERT INTO identities (provider, subject, user_id) VALUES ('code', $1, $2)")
        .bind(&subject)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    let session = create_session(&state, user_id).await?;
    Ok(Json(NewAccountResponse { token: session.token, user_id, code }))
}

/// Entra numa conta existente pelo código.
pub async fn login_code(
    State(state): State<AppState>,
    ClientIp(ip): ClientIp,
    Json(body): Json<CodeLoginRequest>,
) -> Result<Json<LoginResponse>, ApiError> {
    state.limits.code_login.check(ip)?;
    let code = normalize_code(&body.code)
        .ok_or_else(|| ApiError::BadRequest(format!("o código tem {CODE_LEN} letras e números")))?;
    let user_id: Option<Uuid> =
        sqlx::query_scalar("SELECT user_id FROM identities WHERE provider = 'code' AND subject = $1")
            .bind(code_subject(&code))
            .fetch_optional(&state.db)
            .await?;
    let user_id = user_id.ok_or(ApiError::InvalidCode)?;
    create_session(&state, user_id).await.map(Json)
}

/// Login só pelo nome, para desenvolvimento local. Desligado a menos que `ALLOW_DEV_LOGIN=true`.
pub async fn login_dev(
    State(state): State<AppState>,
    Json(body): Json<DevLoginRequest>,
) -> Result<Json<LoginResponse>, ApiError> {
    if !state.allow_dev_login {
        return Err(ApiError::NotFound("login de desenvolvimento desligado".into()));
    }
    let name = body.name.trim();
    if name.is_empty() || name.len() > 100 {
        return Err(ApiError::BadRequest("informe um nome de até 100 caracteres".into()));
    }
    let user_id = find_or_create_user(&state, "dev", name).await?;
    create_session(&state, user_id).await.map(Json)
}

/// Usuário autenticado pelo cabeçalho `Authorization: Bearer <token>`.
pub struct AuthUser {
    pub id: Uuid,
    token_hash: Vec<u8>,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.strip_prefix("Bearer "))
            .map(str::trim)
            .filter(|token| !token.is_empty())
            .ok_or(ApiError::Unauthorized)?;
        let token_hash = hash_token(token);
        let user_id: Option<Uuid> =
            sqlx::query_scalar("SELECT user_id FROM sessions WHERE token_hash = $1 AND expires_at > now()")
                .bind(&token_hash)
                .fetch_optional(&state.db)
                .await?;
        user_id.map(|id| AuthUser { id, token_hash }).ok_or(ApiError::Unauthorized)
    }
}

/// Encerra a sessão atual.
pub async fn logout(State(state): State<AppState>, user: AuthUser) -> Result<StatusCode, ApiError> {
    sqlx::query("DELETE FROM sessions WHERE token_hash = $1").bind(&user.token_hash).execute(&state.db).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Apaga o usuário e tudo dele de forma definitiva.
pub async fn delete_account(State(state): State<AppState>, user: AuthUser) -> Result<StatusCode, ApiError> {
    sqlx::query("DELETE FROM users WHERE id = $1").bind(user.id).execute(&state.db).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codigo_novo_tem_tres_grupos_de_quatro() {
        let code = new_account_code().unwrap();
        let groups: Vec<&str> = code.split('-').collect();
        assert_eq!(groups.len(), 3, "{code}");
        assert!(groups.iter().all(|group| group.len() == 4), "{code}");
        assert!(normalize_code(&code).is_some(), "{code}");
    }

    #[test]
    fn codigos_novos_nao_se_repetem() {
        let codes: std::collections::HashSet<String> = (0..1000).map(|_| new_account_code().unwrap()).collect();
        assert_eq!(codes.len(), 1000);
    }

    #[test]
    fn normaliza_minusculas_espacos_e_hifens() {
        assert_eq!(normalize_code(" k7qm-4xpa 9rtd ").as_deref(), Some("K7QM4XPA9RTD"));
        assert_eq!(normalize_code("K7QM4XPA9RTD").as_deref(), Some("K7QM4XPA9RTD"));
    }

    #[test]
    fn recusa_tamanho_errado_e_letras_que_se_confundem() {
        assert_eq!(normalize_code("K7QM-4XPA"), None);
        assert_eq!(normalize_code("K7QM-4XPA-9RTD-2"), None);
        assert_eq!(normalize_code("O7QM-4XPA-9RTD"), None, "O se confunde com 0");
        assert_eq!(normalize_code("K7QM-4XPA-9RT1"), None, "1 se confunde com I");
        assert_eq!(normalize_code(""), None);
    }

    #[test]
    fn hash_do_codigo_nao_contem_o_codigo() {
        let subject = code_subject("K7QM4XPA9RTD");
        assert!(!subject.contains("K7QM4XPA9RTD"));
        assert_eq!(subject, code_subject("K7QM4XPA9RTD"));
    }
}
