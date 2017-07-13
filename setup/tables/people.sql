CREATE TABLE people
(
    gid               INT NOT NULL DEFAULT NEXTVAL('gid_seq'),
    id                SERIAL,
    valid_from        TIMESTAMPTZ DEFAULT NOW() NOT NULL CONSTRAINT is_chronological CHECK (valid_from < valid_till),
    valid_till        TIMESTAMPTZ,
    email             VARCHAR(255) CONSTRAINT is_email CHECK (email ~ '^[^@]+@([a-zA-Z0-9][a-zA-Z0-9-]*\.)+(xn--[a-zA-Z0-9-]{4,}|[a-zA-Z]{2,})$'),
    phone             VARCHAR(255),
    password_hash     VARCHAR(255),
    data              JSONB NOT NULL DEFAULT '{}',
    modified_by       INT NOT NULL,
    modified          TIMESTAMPTZ,
    created           TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
