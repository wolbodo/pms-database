CREATE OR REPLACE FUNCTION public.fields_get(token TEXT, ref_table VARCHAR(255) DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql
 STABLE
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