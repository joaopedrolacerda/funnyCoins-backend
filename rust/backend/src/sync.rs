//! `POST /v1/sync`: recebe as alterações do aparelho e devolve as do servidor.

use axum::Json;
use axum::extract::State;
use sqlx::types::Json as DbJson;
use uuid::Uuid;

use crate::AppState;
use crate::auth::AuthUser;
use crate::contract::{SyncRecord, SyncRequest, SyncResponse};
use crate::error::ApiError;

/// Limite de registros por requisição. O cliente manda o resto na próxima sincronização.
pub const MAX_CHANGES: usize = 5_000;

#[derive(sqlx::FromRow)]
struct RecordRow {
    id: Uuid,
    kind: String,
    updated_at: i64,
    deleted_at: Option<i64>,
    data: DbJson<serde_json::Value>,
}

pub async fn sync(
    State(state): State<AppState>,
    user: AuthUser,
    Json(request): Json<SyncRequest>,
) -> Result<Json<SyncResponse>, ApiError> {
    if request.changes.len() > MAX_CHANGES {
        return Err(ApiError::BadRequest(format!("envie no máximo {MAX_CHANGES} registros por vez")));
    }
    for record in &request.changes {
        record.validate().map_err(ApiError::BadRequest)?;
    }

    let mut tx = state.db.begin().await?;

    // Trava o usuário: duas sincronizações ao mesmo tempo não podem dar o mesmo número de sequência.
    let mut seq: i64 = sqlx::query_scalar("SELECT last_seq FROM users WHERE id = $1 FOR UPDATE")
        .bind(user.id)
        .fetch_one(&mut *tx)
        .await?;

    // Um cursor maior que o do servidor vem de um banco recriado: manda tudo de novo.
    let cursor = request.cursor.filter(|cursor| *cursor <= seq).unwrap_or(0);

    for record in &request.changes {
        // Grava se for novo ou se o updatedAt recebido for maior. Em empate, mantém o salvo.
        let written = sqlx::query(
            "INSERT INTO records (user_id, id, kind, updated_at, deleted_at, data, seq)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (user_id, id) DO UPDATE SET
                kind = EXCLUDED.kind, updated_at = EXCLUDED.updated_at, deleted_at = EXCLUDED.deleted_at,
                data = EXCLUDED.data, seq = EXCLUDED.seq
             WHERE records.updated_at < EXCLUDED.updated_at",
        )
        .bind(user.id)
        .bind(record.id)
        .bind(&record.kind)
        .bind(record.updated_at)
        .bind(record.deleted_at)
        .bind(DbJson(&record.data))
        .bind(seq + 1)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if written == 1 {
            seq += 1;
        }
    }

    sqlx::query("UPDATE users SET last_seq = $2 WHERE id = $1").bind(user.id).bind(seq).execute(&mut *tx).await?;

    let rows: Vec<RecordRow> = sqlx::query_as(
        "SELECT id, kind, updated_at, deleted_at, data FROM records WHERE user_id = $1 AND seq > $2 ORDER BY seq",
    )
    .bind(user.id)
    .bind(cursor)
    .fetch_all(&mut *tx)
    .await?;

    tx.commit().await?;

    let changes = rows
        .into_iter()
        .map(|row| SyncRecord {
            id: row.id,
            kind: row.kind,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
            data: row.data.0,
        })
        .collect();
    Ok(Json(SyncResponse { cursor: seq, changes }))
}
