CREATE OR REPLACE FUNCTION public.people_roles_get(rights payload_permissions, people_id INT, roles_id INT)
 RETURNS JSONB
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    people_roles JSONB;
    _people_id ALIAS FOR people_id;
    _roles_id ALIAS FOR roles_id;
BEGIN
    SELECT JSONB_AGG((
        SELECT JSONB_OBJECT_AGG(key, value) --FILTER (WHERE key IS NOT NULL)
        FROM JSONB_EACH(
            data
            || JSONB_BUILD_OBJECT(
                'gid', pr.gid,
                '$ref', '/roles/' || pr.roles_id
            )
        )
        WHERE
            rights.permissions->'people_roles'->'view' ? key
    )) INTO people_roles
    FROM people_roles pr
    WHERE valid_till IS NULL AND people_id = _people_id AND roles_id = _roles_id
    GROUP BY pr.people_id;
    RETURN people_roles;
END;
$function$;
