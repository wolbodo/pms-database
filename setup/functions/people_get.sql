CREATE OR REPLACE FUNCTION public.people_get(rights payload_permissions, people_id INT DEFAULT NULL, return_refs BOOLEAN DEFAULT TRUE)
 RETURNS JSONB
 LANGUAGE plpgsql
 STABLE
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
                    'phone', p.phone
                )
                || CASE
                    WHEN return_refs THEN
                        JSONB_BUILD_OBJECT('roles', COALESCE(people_roles.json, '[]'::JSONB))
                    ELSE
                        '{}'::JSONB
                END
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
                        '$ref', '/roles/' || pr.roles_id
                    )
                )
                WHERE
                    key = '$ref' OR rights.permissions->'people_roles'->'view' ? key
            )) AS json
            FROM people_roles pr
            WHERE valid_till IS NULL
            GROUP BY pr.people_id
        ) people_roles ON return_refs AND people_roles.people_id = p.id
        WHERE valid_till IS NULL AND (p.id = _people_id OR _people_id IS NULL)
    ) alias (object)
    WHERE object IS NOT NULL AND object ? 'id';
    RETURN people;
END;
$function$;

CREATE OR REPLACE FUNCTION public.people_get(token TEXT, people_id INT DEFAULT NULL, return_refs BOOLEAN DEFAULT TRUE)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN people_get(rights := permissions_get(token), people_id := people_id, return_refs:= return_refs);
END;
$function$;