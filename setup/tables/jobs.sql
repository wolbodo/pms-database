CREATE TABLE jobs
(
    gid               INT NOT NULL DEFAULT NEXTVAL('gid_seq'),
    id                SERIAL,
    valid_from        TIMESTAMPTZ DEFAULT NOW() NOT NULL CONSTRAINT is_chronological CHECK (valid_from < valid_till),
    valid_till        TIMESTAMPTZ DEFAULT NOW() + interval '15 minutes',
    type              VARCHAR(255) NOT NULL,
    worker            VARCHAR(255),
    state             jobs_state DEFAULT 'queued'::jobs_state,
    name              VARCHAR(255) NOT NULL,
    priority          INT DEFAULT 100,
    data              JSONB NOT NULL DEFAULT '{}',
    modified_by       INT NOT NULL,
    modified          TIMESTAMPTZ,
    created           TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
