CREATE OR REPLACE FUNCTION public.roles_get(rights payload_permissions, roles_id INT DEFAULT NULL, return_refs BOOLEAN DEFAULT TRUE)
 RETURNS JSONB
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    roles JSONB;
    _roles_id ALIAS FOR roles_id;
BEGIN
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
                        '$ref', '/people/' || people_id
                    )
                )
                WHERE
                    key = '$ref' OR rights.permissions->'people_roles'->'view' ? key
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

CREATE OR REPLACE FUNCTION public.roles_get(token TEXT, roles_id INT DEFAULT NULL, return_refs BOOLEAN DEFAULT TRUE)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN roles_get(rights := permissions_get(token), roles_id := roles_id, return_refs:= return_refs);
END;
$function$;