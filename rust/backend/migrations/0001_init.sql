-- Usuários. last_seq é o último número de sequência dado a um registro deste usuário (o cursor).
CREATE TABLE users (
    id UUID PRIMARY KEY,
    last_seq BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Contas de login (Apple, Google) ligadas a um usuário.
CREATE TABLE identities (
    provider TEXT NOT NULL,
    subject TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, subject)
);

CREATE INDEX identities_user_id ON identities (user_id);

-- Sessões. Só o hash SHA-256 do token fica salvo.
CREATE TABLE sessions (
    token_hash BYTEA PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX sessions_user_id ON sessions (user_id);

-- Registros sincronizados. O id vem do aparelho e só é único dentro do usuário.
-- Datas em milissegundos desde 1970 e dinheiro em centavos, como no contrato.
CREATE TABLE records (
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    id UUID NOT NULL,
    kind TEXT NOT NULL,
    updated_at BIGINT NOT NULL,
    deleted_at BIGINT,
    data JSONB NOT NULL,
    seq BIGINT NOT NULL,
    PRIMARY KEY (user_id, id)
);

CREATE INDEX records_user_seq ON records (user_id, seq);
