CREATE OR REPLACE FUNCTION public.permissions_get(token TEXT)
 RETURNS payload_permissions
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    payload JSONB;
    permissions JSONB;
BEGIN
    payload = parse_jwt(token);
    SELECT JSONB_OBJECT_AGG(key, value) INTO permissions FROM (
        SELECT ref_table AS key, JSONB_STRIP_NULLS(COALESCE(JSONB_OBJECT_AGG(key, value) FILTER (WHERE NOT self AND NOT "create"), '{}'::JSONB)
            || JSONB_BUILD_OBJECT('create', CASE
                    WHEN COUNT(*) FILTER (WHERE "create" AND key IS NULL) > 0 THEN '{}'::JSONB
                    ELSE JSONB_OBJECT_AGG(key, value) FILTER (WHERE "create" AND key IS NOT NULL)
                END)
            || JSONB_BUILD_OBJECT('self', JSONB_OBJECT_AGG(key, value) FILTER (WHERE self))) AS value
        FROM (
            SELECT
                pm.ref_table,
                CASE
                    WHEN type IN ('custom'::permissions_type, 'create'::permissions_type) THEN ref_key
                    ELSE type::TEXT
                END AS key,
                r.name = 'self' AS self,
                type = 'create'::permissions_type AS "create",
                CASE
                    WHEN NOT (r.name = 'self') AND type IN ('view'::permissions_type, 'edit'::permissions_type) THEN
                        JSONB_AGG(DISTINCT f.name)
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
            WHERE pr.people_id = (payload->>'user')::INT
            GROUP BY pm.ref_table, pm.type, pm.ref_key, r.name = 'self'
        ) alias
        GROUP BY ref_table
    ) alias;
    RETURN (payload, permissions);
END;
$function$;