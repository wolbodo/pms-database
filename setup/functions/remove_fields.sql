CREATE OR REPLACE FUNCTION public.remove_fields(base JSONB, fields TEXT[])
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    field VARCHAR;
BEGIN
    FOREACH field IN ARRAY fields
    LOOP
        base = base -field;
    END LOOP;
    RETURN base;
END;
$function$;