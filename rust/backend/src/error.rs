use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::json;

/// Erros devolvidos pela API como `{"error": "mensagem"}`.
#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("{0}")]
    BadRequest(String),
    #[error("faça login para continuar")]
    Unauthorized,
    #[error("token de login inválido")]
    InvalidIdentity,
    #[error("código não encontrado: confira se digitou certo")]
    InvalidCode,
    #[error("muitas tentativas: espere um pouco e tente de novo")]
    TooManyRequests,
    #[error("{0}")]
    NotFound(String),
    #[error("erro interno")]
    Internal(String),
}

impl ApiError {
    pub fn internal(error: impl std::fmt::Display) -> Self {
        Self::Internal(error.to_string())
    }
}

impl From<sqlx::Error> for ApiError {
    fn from(error: sqlx::Error) -> Self {
        Self::internal(error)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = match &self {
            Self::BadRequest(_) => StatusCode::BAD_REQUEST,
            Self::Unauthorized | Self::InvalidIdentity | Self::InvalidCode => StatusCode::UNAUTHORIZED,
            Self::NotFound(_) => StatusCode::NOT_FOUND,
            Self::TooManyRequests => StatusCode::TOO_MANY_REQUESTS,
            Self::Internal(detail) => {
                tracing::error!("{detail}");
                StatusCode::INTERNAL_SERVER_ERROR
            }
        };
        (status, Json(json!({ "error": self.to_string() }))).into_response()
    }
}
