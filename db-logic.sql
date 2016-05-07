--FIXME: security:
--        - remove access of viewing functions who expose the SHA256 HMAC secret
--        - limit access to internal functions, including "*_get(rights payload_permissions" functions

CREATE OR REPLACE FUNCTION public.base64url_jsonb(json TEXT, info TEXT DEFAULT ''::TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
  debug1 TEXT;
BEGIN
    RETURN CONVERT_FROM(DECODE(TRANSLATE(json || REPEAT('=', LENGTH(json) * 6 % 8 / 2), '-_',''), 'base64'), 'UTF-8')::JSONB;
EXCEPTION
    WHEN invalid_parameter_value THEN
        --GET STACKED DIAGNOSTICS debug1 = MESSAGE_TEXT;
        --RAISE EXCEPTION  'E: % %', info, debug1;
        RAISE EXCEPTION '%', jsonb_error('Invalid base64 token');
END
$function$;


CREATE OR REPLACE FUNCTION public.jsonb_base64url(jsonbytes JSONB)
 RETURNS TEXT
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN TRANSLATE(ENCODE(jsonbytes::TEXT::BYTEA, 'base64'), '+/=', '-_');
END
$function$;


CREATE OR REPLACE FUNCTION public.jsonb_error(format TEXT, VARIADIC args ANYARRAY DEFAULT ARRAY[]::INTEGER[])
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN JSONB_BUILD_OBJECT('error', FORMAT(format, VARIADIC args));
END
$function$;


CREATE OR REPLACE FUNCTION public.to_date(stamp TIMESTAMPTZ)
 RETURNS VARCHAR
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN TO_CHAR(stamp, 'YYYY-MM-DD"T"HH24:MI:SS.MSOF":00"');
END
$function$;


CREATE OR REPLACE FUNCTION public.parse_jwt(token TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
  header JSONB;
  payload JSONB;
  match TEXT[];
BEGIN
    match = REGEXP_MATCHES(token, '^(([a-zA-Z0-9_=-]+)\.([a-zA-Z0-9_=-]+))\.([a-zA-Z0-9_=-]+)$');
    header = base64url_jsonb(match[2]);
    payload = base64url_jsonb(match[3]);
    IF match IS NULL OR match[4] != TRANSLATE(ENCODE(HMAC(match[1], :'token_sha256_key', 'sha256'), 'base64'), '+/=', '-_') THEN
        RAISE EXCEPTION '%', jsonb_error('Invalid signature');
    END IF;
    IF NOT payload ? 'exp' OR (payload->>'exp')::INT < FLOOR(EXTRACT(EPOCH FROM NOW())) THEN
        RAISE EXCEPTION '%', jsonb_error('Expired signature');
    END IF;
    RETURN payload;
END
$function$;


CREATE OR REPLACE FUNCTION public.login(emailaddress TEXT, password TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
  header JSONB;
  payload JSONB;
  content TEXT;
  signature TEXT;
  token TEXT;
BEGIN
    header = '{"type":"jwt", "alg":"hs256"}'::JSONB;
    SELECT
        JSONB_BUILD_OBJECT(
            'user', p.id,
            'exp', FLOOR(EXTRACT(EPOCH FROM NOW() + INTERVAL '31 days'))
        ) INTO STRICT payload
        FROM people p
            JOIN people_roles pr ON pr.people_id = p.id AND p.valid_till IS NULL AND pr.valid_till IS NULL
            JOIN roles r ON pr.roles_id = r.id AND r.valid_till IS NULL
        WHERE p.email = emailaddress AND CRYPT(password, p.password_hash) = p.password_hash AND r.name = 'login';
    content = jsonb_base64url(header) || '.' || jsonb_base64url(payload);
    signature = TRANSLATE(ENCODE(HMAC(content, :'token_sha256_key', 'sha256'), 'base64'), '+/=', '-_');
    token = content || '.' || signature;
    RETURN JSONB_BUILD_OBJECT(
        'token', token,
        'permissions', (permissions_get(token := token)).permissions
    );
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION '%', jsonb_error('Username or password wrong');
    WHEN TOO_MANY_ROWS THEN
        RAISE EXCEPTION '%', jsonb_error('More than one entry found, please contact an admin or board member to fix this');
END
$function$;


CREATE OR REPLACE FUNCTION public.has_role(self_id INT, role_name VARCHAR)
 RETURNS BOOL
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM FROM roles r
                JOIN people_roles pr ON (pr.roles_id = r.id OR r.name = 'self') AND pr.valid_till IS NULL AND r.valid_till IS NULL
                JOIN people p ON pr.people_id = p.id AND r.name != 'self' AND p.valid_till IS NULL
            WHERE p.id = self_id AND r.name = role_name;
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    RETURN TRUE;
END;
$function$;


DROP TYPE IF EXISTS "payload_permissions" CASCADE;
CREATE TYPE "payload_permissions" AS (
  payload   JSONB,
  permissions  JSONB
);


CREATE OR REPLACE FUNCTION public.permissions_get(token TEXT)
 RETURNS payload_permissions
 LANGUAGE plpgsql
AS $function$
DECLARE
    payload JSONB;
    permissions JSONB;
BEGIN
    payload = parse_jwt(token);
    SELECT JSONB_OBJECT_AGG(ref_table, json) INTO permissions FROM (
        SELECT
            ref_table,
            JSONB_OBJECT_AGG(rule.key, rule.value) FILTER (WHERE rule.key IS NOT NULL) ||
                COALESCE(NULLIF(
                    JSONB_BUILD_OBJECT('self', COALESCE(JSONB_OBJECT_AGG(selfrule.key, selfrule.value) FILTER (WHERE selfrule.key IS NOT NULL), '{}'::JSONB)),
                    '{"self":{}}'
                ),'{}') AS json
        FROM (
            SELECT pm.ref_table,
                CASE
                    WHEN NOT (r.name = 'self') AND type IN ('view'::permissions_type, 'edit'::permissions_type) THEN
                        JSONB_BUILD_OBJECT(type, JSONB_AGG(DISTINCT f.name))
                    WHEN type IN ('view'::permissions_type, 'edit'::permissions_type) THEN
                        JSONB_BUILD_OBJECT('self', JSONB_BUILD_OBJECT(type, JSONB_AGG(DISTINCT f.name)))
                    WHEN type = 'create'::permissions_type THEN
                        JSONB_BUILD_OBJECT(type, CASE WHEN ref_key IS NULL THEN '{}'::JSONB ELSE JSONB_BUILD_OBJECT(ref_key, CASE WHEN JSONB_AGG(ref_value) @> 'null'::JSONB THEN '"*"'::JSONB ELSE JSONB_AGG(ref_value) END) END)
                    WHEN type = 'custom'::permissions_type THEN
                        JSONB_BUILD_OBJECT(ref_key, COALESCE(NULLIF(JSONB_AGG(ref_value),'[null]'),'true'::JSONB))
                END AS json
            FROM permissions pm
                JOIN roles_permissions rpm ON pm.id = rpm.permissions_id AND pm.valid_till IS NULL AND rpm.valid_till IS NULL
                JOIN roles r ON r.id = rpm.roles_id AND r.valid_till IS NULL
                JOIN people_roles pr ON (pr.roles_id = r.id OR r.name = 'self') AND pr.valid_till IS NULL
                --JOIN people p ON pr.people_id = p.id AND p.id = _self_id AND (r.name != 'self' OR _people_id = _self_id) AND p.valid_till IS NULL
                LEFT JOIN fields f ON pm.ref_key = 'fields' AND pm.ref_value = f.id AND f.valid_till IS NULL
            WHERE pr.people_id = (payload->>'user')::INT
            GROUP BY pm.ref_table, pm.type, pm.ref_key, r.name = 'self'
            ORDER BY ref_key NULLS FIRST --so "create": {} will be overwritten by "create": {"key":[values]}
        ) rules
            LEFT JOIN JSONB_EACH(rules.json - 'self') rule ON TRUE
            LEFT JOIN JSONB_EACH(rules.json->'self') selfrule ON TRUE
        GROUP BY rules.ref_table
    ) alias;
    RETURN (payload, permissions);
END;
$function$;


CREATE OR REPLACE FUNCTION public.roles_permissions_get(token TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    payload JSONB;
    permissions JSONB;
BEGIN
    payload = parse_jwt(token);
    SELECT JSONB_BUILD_OBJECT('roles_permissions', JSONB_OBJECT_AGG(r_id, json)) INTO permissions FROM (
        SELECT r_id, JSONB_OBJECT_AGG(ref_table, json) AS json FROM (
            SELECT
                rules.r_id,
                ref_table,
                JSONB_OBJECT_AGG(rule.key, rule.value) FILTER (WHERE rule.key IS NOT NULL) AS json
            FROM (
                SELECT r.id AS r_id, pm.ref_table,
                    CASE
                        WHEN type IN ('view'::permissions_type, 'edit'::permissions_type) THEN
                            JSONB_BUILD_OBJECT(type, JSONB_AGG(DISTINCT f.name))
                        WHEN type = 'create'::permissions_type THEN
                            JSONB_BUILD_OBJECT(type, CASE WHEN ref_key IS NULL THEN '{}'::JSONB ELSE JSONB_BUILD_OBJECT(ref_key, CASE WHEN JSONB_AGG(ref_value) @> 'null'::JSONB THEN '"*"'::JSONB ELSE JSONB_AGG(ref_value) END) END)
                        WHEN type = 'custom'::permissions_type THEN
                            JSONB_BUILD_OBJECT(ref_key, COALESCE(NULLIF(JSONB_AGG(ref_value),'[null]'),'true'::JSONB))
                    END AS json
                FROM permissions pm
                    JOIN roles_permissions rpm ON pm.id = rpm.permissions_id AND pm.valid_till IS NULL AND rpm.valid_till IS NULL
                    JOIN roles r ON r.id = rpm.roles_id AND r.valid_till IS NULL
                    LEFT JOIN fields f ON pm.ref_key = 'fields' AND pm.ref_value = f.id AND f.valid_till IS NULL
                GROUP BY r.id, r.name, pm.ref_table, pm.type, pm.ref_key
                ORDER BY ref_key NULLS FIRST --so "create": {} will be overwritten by "create": {"key":[values]}
            ) rules
                LEFT JOIN JSONB_EACH(rules.json) rule ON TRUE
            GROUP BY rules.r_id, rules.ref_table
        ) alias
        GROUP BY alias.r_id
    ) alias;
    RETURN permissions;
END;
$function$;


CREATE OR REPLACE FUNCTION public.data_merge(rights payload_permissions, ref_table VARCHAR, base JSONB = '{}'::JSONB, update JSONB = '{}'::JSONB, remove BOOL DEFAULT FALSE)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    kv record;
    viewfields JSONB;
    editfields JSONB;
    createfields JSONB;
    changed BOOL;
BEGIN
    --OK construct: this construct is chosen because a IF NOT(NULL) => NULL,
    -- since we resolve quite some JSONB paths (which resolves to NULL if the key/path doesn't exist)
    -- this IF OK ELSE ERROR construct is way less verbose than checking explicitly for NULL or key exists.
    changed = FALSE;
    viewfields = rights.permissions->ref_table->'view';
    editfields = rights.permissions->ref_table->'edit';
    createfields = rights.permissions->ref_table->'create';
    IF ref_table = 'people' AND (base->>'id')::INT = (rights.payload->>'user')::INT THEN
        viewfields = COALESCE(viewfields, '[]'::JSONB) || COALESCE(rights.permissions->ref_table->'self'->'view', '[]'::JSONB);
        editfields = COALESCE(editfields, '[]'::JSONB) || COALESCE(rights.permissions->ref_table->'self'->'edit', '[]'::JSONB);
    END IF;
    IF base = '{}'::JSONB THEN
        IF rights.permissions->ref_table ? 'create' THEN
            --OK construct
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Creating "%s" not allowed', ref_table);
            RETURN NULL;
        END IF;
    ELSE
        IF base->>'gid' = update->>'gid' THEN
            --OK construct
        ELSEIF base->>'gid' != update->>'gid' THEN
            RAISE EXCEPTION '%', jsonb_error('Outdated gid %s, expected current gid %s', update->>'gid', base->>'gid');
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Must supply gid on update');
        END IF;
    END IF;
    IF remove THEN
        IF rights.permissions->ref_table ? 'create' THEN
            --OK construct
            FOR kv IN (SELECT * FROM JSONB_EACH(createfields))
            LOOP
                IF createfields->kv.key = '*' OR base ? kv.key AND base->kv.key @> kv.value THEN
                    --OK construct
                ELSE
                    RAISE EXCEPTION '%', jsonb_error('Removing "%s" value %s not allowed', kv.key, kv.value);
                END IF;
            END LOOP;
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Removing "%s" not allowed', ref_table);
        END IF;
    END IF;
    FOR kv IN (SELECT * FROM JSONB_EACH(update))
    LOOP
        IF editfields ? kv.key THEN
            --OK construct
            IF viewfields ? kv.key THEN
                IF base->kv.key = kv.value THEN
                    --OK construct / nothing changed
                ELSE
                    changed = TRUE;
                END IF;
            ELSE
                changed = TRUE;
            END IF;
        ELSEIF viewfields ? kv.key AND base->kv.key = kv.value THEN
            --OK construct
        ELSEIF base = '{}'::JSONB THEN
            IF createfields ? kv.key THEN
                IF createfields->kv.key = '*' OR createfields->kv.key <@ kv.value THEN
                    --OK construct
                ELSE
                    RAISE EXCEPTION '%', jsonb_error('Creating "%s" with value %s is not allowed', kv.key, kv.value);
                END IF;
            ELSE
                RAISE EXCEPTION '%', jsonb_error('Creating "%s" is not allowed', kv.key);
            END IF;
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Editing "%s" is not allowed', kv.key);
        END IF;
    END LOOP;
    IF NOT remove AND base != '{}'::JSONB AND NOT changed THEN
        RAISE EXCEPTION '%', jsonb_error('Editing nothing is not allowed');
    ELSEIF NOT remove AND update = '{}'::JSONB THEN
        RAISE EXCEPTION '%', jsonb_error('Creating nothing is not allowed');
    END IF;
    RETURN base || update;
END;
$function$;


CREATE OR REPLACE FUNCTION public.remove_base(base JSONB)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    field VARCHAR;
BEGIN
    FOREACH field IN ARRAY ARRAY['gid', 'id'] LOOP --'valid_from', 'valid_till', 'password_hash', 'modified_by', 'modified', 'created'
        base = base -field;
    END LOOP;
    RETURN base;
END;
$function$;


CREATE OR REPLACE FUNCTION public.people_get(rights payload_permissions, people_id INT DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    people JSONB;
    _people_id ALIAS FOR people_id;
BEGIN
    SELECT JSONB_BUILD_OBJECT('people', JSONB_OBJECT_AGG(object->>'id', object)) INTO people
    FROM (
        SELECT (
            SELECT JSONB_OBJECT_AGG(key, value)
            FROM JSONB_EACH(
                p.data
                || JSONB_BUILD_OBJECT(
                    'gid', p.gid,
                    'id', p.id,
                    'email', p.email,
                    'phone', p.phone,
                    'roles', COALESCE(people_roles.json, '[]'::JSONB)
                )
            )
            WHERE
                rights.permissions->'people'->'view' ? key
                OR (
                    p.id = (rights.payload->>'user')::INT
                    AND rights.permissions->'people'->'self'->'view' ? key
                )
        )
        FROM people p
        LEFT JOIN (
            SELECT pr.people_id, JSONB_AGG((
                SELECT JSONB_OBJECT_AGG(key, value) --FILTER (WHERE key IS NOT NULL)
                FROM JSONB_EACH(
                    data
                    || JSONB_BUILD_OBJECT(
                        'gid', pr.gid,
                        '$ref', '/roles/' || pr.roles_id,
                        'roles_id', pr.roles_id
                    )
                )
                WHERE
                    rights.permissions->'people_roles'->'view' ? key
            )) AS json
            FROM people_roles pr
            WHERE valid_till IS NULL
            GROUP BY pr.people_id
        ) people_roles ON people_roles.people_id = p.id
        WHERE valid_till IS NULL AND (p.id = _people_id OR _people_id IS NULL)
    ) alias (object)
    WHERE object IS NOT NULL AND object ? 'id';
    RETURN people;
END;
$function$;


CREATE OR REPLACE FUNCTION public.people_get(token TEXT, people_id INT DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN people_get(rights := permissions_get(token), people_id := people_id);
END;


$function$;
CREATE OR REPLACE FUNCTION public.people_set(token TEXT, people_id INT, data JSONB)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
    _data ALIAS FOR data;
BEGIN
    rights = permissions_get(token);
    _data = remove_base(data_merge(
        rights := rights,
        ref_table := 'people',
        base := people_get(rights, people_id)->'people'->people_id::TEXT,
        update := _data
    ));

    UPDATE people SET valid_till = NOW() WHERE id = people_id AND valid_till IS NULL;

    INSERT INTO people (id, valid_from, email, phone, password_hash, modified_by, data)
        SELECT id, valid_till, _data->>'email', _data->>'phone', password_hash, (rights.payload->>'user')::INT, _data -'email' -'phone'
            FROM people WHERE id = people_id ORDER BY valid_till DESC LIMIT 1;

    RETURN people_get(rights, people_id);
END;
$function$;


CREATE OR REPLACE FUNCTION public.people_add(token TEXT, data JSONB)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
    _data ALIAS FOR data;
    people_id INT;
BEGIN
    rights = permissions_get(token);
    _data = remove_base(data_merge(
        rights := rights,
        ref_table := 'people',
        update := _data
    ));

    INSERT INTO people (email, phone, modified_by, data)
        VALUES (_data->>'email', _data->>'phone', (rights.payload->>'user')::INT, _data -'email' -'phone') RETURNING id INTO people_id;

    RETURN people_get(rights, people_id);
END;
$function$;


CREATE OR REPLACE FUNCTION public.people_del(token TEXT, people_id INT)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
BEGIN
    rights = permissions_get(token);
    PERFORM data_merge(
        rights := rights,
        ref_table := 'people',
        base := people_get(rights, people_id)->'people'->people_id::TEXT,
        remove := TRUE
    );

    UPDATE people SET valid_till = NOW() WHERE id = people_id AND valid_till IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_error('No active person with id=%s found', people_id);
    END IF;
    RETURN 'true'::JSONB;--people_get(rights, people_id);
END;
$function$;


CREATE OR REPLACE FUNCTION public.roles_get(token TEXT, roles_id INT DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    roles JSONB;
    _roles_id ALIAS FOR roles_id;
BEGIN
    --NOTE: only expose roles to people who can log in
    PERFORM parse_jwt(token);
    SELECT JSONB_BUILD_OBJECT('roles', COALESCE(JSONB_OBJECT_AGG(object->>'id', object), '{}'::JSONB)) INTO roles
    FROM (
        SELECT (
            SELECT JSONB_OBJECT_AGG(key, value)
            FROM JSONB_EACH(
                r.data
                || JSONB_BUILD_OBJECT(
                    'gid', r.gid,
                    'id', r.id,
                    'name', r.name,
                    'members', COALESCE(people_roles.json, '[]'::JSONB)
                )
            )
            WHERE
                rights.permissions->'roles'->'view' ? key AND r.name != 'self'
        )
        FROM roles r
        LEFT JOIN (
            SELECT pr.roles_id, JSONB_AGG((
                SELECT JSONB_OBJECT_AGG(key, value) --FILTER (WHERE key IS NOT NULL)
                FROM JSONB_EACH(
                    data
                    || JSONB_BUILD_OBJECT(
                        'gid', gid,
                        '$ref', '/people/' || people_id,
                        'people_id', people_id
                    )
                )
                WHERE
                    rights.permissions->'people_roles'->'view' ? key
            )) AS json
            FROM people_roles pr
            WHERE valid_till IS NULL
            GROUP BY pr.roles_id
        ) people_roles ON people_roles.roles_id = r.id
        WHERE r.valid_till IS NULL AND (r.id = _roles_id OR _roles_id IS NULL)
    ) alias (object)
    WHERE object IS NOT NULL AND object ? 'id';
    RETURN roles;
END;
$function$;


CREATE OR REPLACE FUNCTION public.roles_set(token TEXT, roles_id INT, data JSONB)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
    _data ALIAS FOR data;
BEGIN
    rights = permissions_get(token);
    _data = remove_base(data_merge(
        rights := rights,
        ref_table := 'roles',
        base := roles_get(rights, roles_id)->'roles'->roles_id::TEXT,
        update := _data
    ));

    UPDATE roles SET valid_till = NOW() WHERE id = roles_id AND valid_till IS NULL;

    INSERT INTO roles (id, valid_from, name, modified_by, data)
        SELECT id, valid_till, _data->>'name', (rights.payload->>'user')::INT, _data -'name'
            FROM roles WHERE id = roles_id ORDER BY valid_till DESC LIMIT 1;

    RETURN roles_get(rights, roles_id);
END;
$function$;


CREATE OR REPLACE FUNCTION public.roles_add(token TEXT, data JSONB)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
    _data ALIAS FOR data;
    roles_id INT;
BEGIN
    rights = permissions_get(token);
    _data = remove_base(data_merge(
        rights := rights,
        ref_table := 'roles',
        update := _data
    ));

    INSERT INTO roles (name, modified_by, data)
        VALUES (_data->>'name', (rights.payload->>'user')::INT, _data -'name') RETURNING id INTO roles_id;

    RETURN roles_get(rights, roles_id);
END;
$function$;


CREATE OR REPLACE FUNCTION public.fields_get(token TEXT, ref_table VARCHAR(255) DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    fields JSONB;
    _ref_table ALIAS FOR ref_table;
BEGIN
    --NOTE: only expose fields to people who can log in
    PERFORM parse_jwt(token);
    SELECT JSONB_BUILD_OBJECT('fields', JSONB_OBJECT_AGG(object->>'name', object)) INTO fields
        FROM (
            SELECT
                JSONB_BUILD_OBJECT(
                    'name', f.ref_table,
                    'type', 'object',
                    'properties', JSONB_OBJECT_AGG(
                        f.name,
                        COALESCE(f.data, '{}'::JSONB) || JSONB_BUILD_OBJECT('id', f.id)
                    )
                )
                || COALESCE(fm.data, '{}'::JSONB)
            FROM fields f
                LEFT JOIN fields fm ON fm.valid_till IS NULL AND fm.name IS NULL AND fm.ref_table = f.ref_table
            WHERE f.valid_till IS NULL AND (f.ref_table = _ref_table OR _ref_table IS NULL) AND f.name IS NOT NULL
            GROUP BY f.ref_table, fm.data
        ) alias (object);
    RETURN fields;
END;
$function$;

