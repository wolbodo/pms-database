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