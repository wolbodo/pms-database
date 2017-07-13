-- NOTE: Only one active meta field (name IS NULL) is allowed per table, and one active name per table.
CREATE UNIQUE INDEX ON fields (id) WHERE valid_till IS NULL;
CREATE UNIQUE INDEX ON fields (ref_table) WHERE valid_till IS NULL AND name IS NULL;
CREATE UNIQUE INDEX ON fields (ref_table, name) WHERE valid_till IS NULL;

CREATE UNIQUE INDEX ON people (id) WHERE valid_till IS NULL;
CREATE UNIQUE INDEX ON people (email) WHERE valid_till IS NULL;
CREATE UNIQUE INDEX ON people ((data->>'nickname')) WHERE valid_till IS NULL;

CREATE UNIQUE INDEX ON permissions (id) WHERE valid_till IS NULL;
CREATE UNIQUE INDEX ON permissions (ref_table, type, ref_key, ref_value) WHERE valid_till IS NULL;

CREATE UNIQUE INDEX ON roles (id) WHERE valid_till IS NULL;
CREATE UNIQUE INDEX ON roles (name) WHERE valid_till IS NULL;

CREATE UNIQUE INDEX ON people_roles (people_id, roles_id) WHERE valid_till IS NULL;

CREATE UNIQUE INDEX ON roles_permissions (roles_id, permissions_id) WHERE valid_till IS NULL;
