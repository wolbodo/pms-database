CREATE OR REPLACE FUNCTION public.jsonb_base64url(jsonbytes JSONB)
 RETURNS TEXT
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    RETURN TRANSLATE(ENCODE(jsonbytes::TEXT::BYTEA, 'base64'), '+/=', '-_');
END
$function$;