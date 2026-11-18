//! Limite de tentativas por endereço IP, guardado em memória.
//! Serve para um servidor só: com várias réplicas, cada uma conta separado.

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use axum::extract::{ConnectInfo, FromRequestParts};
use axum::http::request::Parts;

use crate::AppState;
use crate::error::ApiError;

/// Janela fixa: no máximo `max` tentativas a cada `window` por IP.
pub struct RateLimiter {
    max: u32,
    window: Duration,
    hits: Mutex<HashMap<IpAddr, (Instant, u32)>>,
}

impl RateLimiter {
    pub fn new(max: u32, window: Duration) -> Self {
        Self { max, window, hits: Mutex::new(HashMap::new()) }
    }

    /// Conta uma tentativa. Sem IP conhecido (só nos testes), não limita.
    pub fn check(&self, ip: Option<IpAddr>) -> Result<(), ApiError> {
        self.check_at(ip, Instant::now())
    }

    fn check_at(&self, ip: Option<IpAddr>, now: Instant) -> Result<(), ApiError> {
        let Some(ip) = ip else { return Ok(()) };
        let mut hits = self.hits.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        // Limpa as janelas vencidas de vez em quando para a memória não crescer sem fim.
        if hits.len() > 10_000 {
            hits.retain(|_, (start, _)| now.duration_since(*start) < self.window);
        }
        let entry = hits.entry(ip).or_insert((now, 0));
        if now.duration_since(entry.0) >= self.window {
            *entry = (now, 0);
        }
        if entry.1 >= self.max {
            return Err(ApiError::TooManyRequests);
        }
        entry.1 += 1;
        Ok(())
    }
}

/// Limites das rotas de login por código.
pub struct Limits {
    /// Criar conta: 10 por hora por IP.
    pub new_account: RateLimiter,
    /// Entrar com código: 30 a cada 15 minutos por IP.
    pub code_login: RateLimiter,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            new_account: RateLimiter::new(10, Duration::from_secs(60 * 60)),
            code_login: RateLimiter::new(30, Duration::from_secs(15 * 60)),
        }
    }
}

/// IP de quem fez o pedido.
/// Atrás de um proxy (como o do Railway), vem do cabeçalho em `CLIENT_IP_HEADER`, por exemplo `x-real-ip`.
/// Sem proxy, vem da conexão.
pub struct ClientIp(pub Option<IpAddr>);

impl FromRequestParts<AppState> for ClientIp {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        if let Some(name) = &state.client_ip_header {
            // Em listas como o x-forwarded-for, o último endereço é o que o proxy viu.
            let from_header = parts
                .headers
                .get(name.as_str())
                .and_then(|value| value.to_str().ok())
                .and_then(|value| value.rsplit(',').next())
                .and_then(|value| value.trim().parse().ok());
            if from_header.is_some() {
                return Ok(Self(from_header));
            }
        }
        let from_socket = parts.extensions.get::<ConnectInfo<SocketAddr>>().map(|info| info.0.ip());
        Ok(Self(from_socket))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(last: u8) -> Option<IpAddr> {
        Some(IpAddr::from([10, 0, 0, last]))
    }

    #[test]
    fn bloqueia_depois_do_maximo_e_libera_na_proxima_janela() {
        let limiter = RateLimiter::new(2, Duration::from_secs(60));
        let start = Instant::now();
        assert!(limiter.check_at(ip(1), start).is_ok());
        assert!(limiter.check_at(ip(1), start).is_ok());
        assert!(matches!(limiter.check_at(ip(1), start), Err(ApiError::TooManyRequests)));
        assert!(limiter.check_at(ip(1), start + Duration::from_secs(61)).is_ok());
    }

    #[test]
    fn cada_ip_tem_sua_conta() {
        let limiter = RateLimiter::new(1, Duration::from_secs(60));
        let now = Instant::now();
        assert!(limiter.check_at(ip(1), now).is_ok());
        assert!(limiter.check_at(ip(2), now).is_ok());
        assert!(limiter.check_at(ip(1), now).is_err());
    }

    #[test]
    fn sem_ip_nao_limita() {
        let limiter = RateLimiter::new(1, Duration::from_secs(60));
        for _ in 0..5 {
            assert!(limiter.check(None).is_ok());
        }
    }
}
