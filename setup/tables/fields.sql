CREATE TABLE fields
(
    gid               INT NOT NULL DEFAULT NEXTVAL('gid_seq'),
    id                SERIAL,
    valid_from        TIMESTAMPTZ DEFAULT NOW() NOT NULL CONSTRAINT is_chronological CHECK (valid_from < valid_till),
    valid_till        TIMESTAMPTZ,
    ref_table         VARCHAR(255) NOT NULL,
    name              VARCHAR(255),
    data              JSONB NOT NULL DEFAULT '{}',
    modified_by       INT NOT NULL,
    modified          TIMESTAMPTZ,
    created           TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
