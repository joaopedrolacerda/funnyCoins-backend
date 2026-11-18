//! Contrato da API de sincronização. Ver `shared/API.md` e `SyncModels.swift`.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

/// Um registro como trafega na API: `{ id, kind, updatedAt, deletedAt, data }`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncRecord {
    pub id: Uuid,
    pub kind: String,
    /// Milissegundos desde 1970.
    pub updated_at: i64,
    /// Omitido ou `null` quando o registro está ativo.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub deleted_at: Option<i64>,
    pub data: Value,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncRequest {
    pub cursor: Option<i64>,
    #[serde(default)]
    pub changes: Vec<SyncRecord>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncResponse {
    pub cursor: i64,
    pub changes: Vec<SyncRecord>,
}

// Formato de `data` para cada tipo. Servem só para validar: o servidor guarda o JSON recebido,
// então campos novos que o app venha a mandar não se perdem.

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
struct ProfileData {
    monthly_essential_cost_cents: i64,
    target_months: i64,
    invest_percent: i64,
    pet_name: String,
    pet_color: String,
    created_at: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
struct CashEntryData {
    title: String,
    amount_cents: i64,
    date: i64,
    kind: String,
    category: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
struct BillData {
    name: String,
    amount_cents: i64,
    due_day: i64,
    paid_months: Vec<String>,
    created_at: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
struct ReserveMovementData {
    amount_cents: i64,
    date: i64,
    note: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
struct InvestmentData {
    name: String,
    modality: String,
    amount_cents: i64,
    date: i64,
}

fn check<T: serde::de::DeserializeOwned>(data: &Value) -> Result<(), String> {
    T::deserialize(data).map(|_| ()).map_err(|error| error.to_string())
}

impl SyncRecord {
    /// Confere se `kind` é conhecido e se `data` tem os campos do contrato.
    pub fn validate(&self) -> Result<(), String> {
        let result = match self.kind.as_str() {
            "profile" => check::<ProfileData>(&self.data),
            "cashEntry" => check::<CashEntryData>(&self.data),
            "bill" => check::<BillData>(&self.data),
            "reserveMovement" => check::<ReserveMovementData>(&self.data),
            "investment" => check::<InvestmentData>(&self.data),
            other => return Err(format!("registro {}: kind desconhecido \"{other}\"", self.id)),
        };
        result.map_err(|error| format!("registro {} ({}): {error}", self.id, self.kind))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn record(kind: &str, data: Value) -> SyncRecord {
        SyncRecord { id: Uuid::new_v4(), kind: kind.into(), updated_at: 1, deleted_at: None, data }
    }

    #[test]
    fn aceita_os_tipos_do_contrato() {
        let entry =
            json!({ "title": "Salário", "amountCents": 500000, "date": 1, "kind": "income", "category": "salary" });
        assert!(record("cashEntry", entry).validate().is_ok());
        let movement = json!({ "amountCents": -100, "date": 1, "note": "" });
        assert!(record("reserveMovement", movement).validate().is_ok());
    }

    #[test]
    fn recusa_kind_desconhecido_e_campo_faltando() {
        assert!(record("goal", json!({})).validate().is_err());
        let sem_valor = json!({ "title": "x", "date": 1, "kind": "income", "category": "salary" });
        assert!(record("cashEntry", sem_valor).validate().is_err());
        let valor_com_virgula = json!({ "name": "x", "modality": "cdb", "amountCents": 10.5, "date": 1 });
        assert!(record("investment", valor_com_virgula).validate().is_err());
    }

    #[test]
    fn deleted_at_e_omitido_quando_ativo() {
        let text = serde_json::to_string(&record("reserveMovement", json!({}))).unwrap();
        assert!(!text.contains("deletedAt"));
        let parsed: SyncRecord = serde_json::from_str(
            r#"{"id":"6f1c4b8e-0000-4000-8000-000000000001","kind":"bill","updatedAt":5,"deletedAt":null,"data":{}}"#,
        )
        .unwrap();
        assert_eq!(parsed.deleted_at, None);
    }
}
