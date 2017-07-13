CREATE OR REPLACE FUNCTION public.base64url_jsonb(json TEXT, info TEXT DEFAULT ''::TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql
 IMMUTABLE
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