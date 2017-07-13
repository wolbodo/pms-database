CREATE OR REPLACE FUNCTION public.roles_permissions_get(rights payload_permissions, roles_id INT DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    _roles_id ALIAS FOR roles_id;
    permissions JSONB;
BEGIN
    SELECT JSONB_BUILD_OBJECT('roles_permissions', JSONB_OBJECT_AGG(key, value)) INTO permissions FROM (
        SELECT r_id AS key, JSONB_OBJECT_AGG(key, value) AS value FROM (
            SELECT r_id, ref_table AS key, JSONB_STRIP_NULLS(COALESCE(JSONB_OBJECT_AGG(key, value) FILTER (WHERE NOT "create"), '{}'::JSONB)
                || JSONB_BUILD_OBJECT('create', CASE
                        WHEN COUNT(*) FILTER (WHERE "create" AND key IS NULL) > 0 THEN '{}'::JSONB
                        ELSE JSONB_OBJECT_AGG(key, value) FILTER (WHERE "create" AND key IS NOT NULL)
                    END)
                ) AS value
            FROM (
                SELECT
                    r.id AS r_id,
                    pm.ref_table,
                    CASE
                        WHEN type IN ('custom'::permissions_type, 'create'::permissions_type) THEN ref_key
                        ELSE type::TEXT
                    END AS key,
                    type = 'create'::permissions_type AS "create",
                    CASE
                        WHEN type IN ('view'::permissions_type, 'edit'::permissions_type) THEN
                            JSONB_AGG(DISTINCT f.name)
                        WHEN type = 'create'::permissions_type THEN
                            CASE WHEN JSONB_AGG(ref_value) @> 'null'::JSONB THEN '"*"'::JSONB ELSE JSONB_AGG(ref_value) END
                        WHEN type = 'custom'::permissions_type THEN
                            COALESCE(NULLIF(JSONB_AGG(ref_value),'[null]'), 'true'::JSONB)
                    END AS value
                FROM permissions pm
                    JOIN roles_permissions rpm ON pm.id = rpm.permissions_id AND pm.valid_till IS NULL AND rpm.valid_till IS NULL
                    JOIN roles r ON r.id = rpm.roles_id AND r.valid_till IS NULL
                    JOIN people_roles pr ON (pr.roles_id = r.id OR r.name = 'self') AND pr.valid_till IS NULL
                    --JOIN people p ON pr.people_id = p.id AND p.id = _self_id AND (r.name != 'self' OR _people_id = _self_id) AND p.valid_till IS NULL
                    LEFT JOIN fields f ON pm.ref_key = 'fields' AND pm.ref_value = f.id AND f.valid_till IS NULL
                WHERE r.id = _roles_id OR _roles_id IS NULL
                GROUP BY r_id, pm.ref_table, pm.type, pm.ref_key
            ) alias
            GROUP BY r_id, ref_table
        ) alias
        GROUP BY r_id
    ) alias;
    RETURN permissions;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roles_permissions_get(token TEXT, roles_id INT DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN roles_permissions_get(rights := permissions_get(token), roles_id := roles_id);
END;
$function$;