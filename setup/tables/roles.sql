CREATE TABLE roles
(
    gid               INT NOT NULL DEFAULT NEXTVAL('gid_seq'),
    id                SERIAL,
    valid_from        TIMESTAMPTZ DEFAULT NOW() NOT NULL CONSTRAINT is_chronological CHECK (valid_from < valid_till),
    valid_till        TIMESTAMPTZ,
    name              VARCHAR(255) NOT NULL,
    data              JSONB NOT NULL DEFAULT '{}',
    modified_by       INT NOT NULL,
    modified          TIMESTAMPTZ,
    created           TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
