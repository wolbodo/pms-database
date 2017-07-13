CREATE OR REPLACE FUNCTION public.parse_jwt(token TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    header JSONB;
    payload JSONB;
    match TEXT[];
BEGIN
    match = REGEXP_MATCHES(token, '^(([a-zA-Z0-9_=-]+)\.([a-zA-Z0-9_=-]+))\.([a-zA-Z0-9_=-]+)$');
    header = base64url_jsonb(match[2]);
    payload = base64url_jsonb(match[3]);
    IF match IS NULL OR match[4] != TRANSLATE(ENCODE(HMAC(match[1], 'token_sha256_key', 'sha256'), 'base64'), '+/=', '-_') THEN
        RAISE EXCEPTION '%', jsonb_error('Invalid signature');
    END IF;
    IF NOT payload ? 'exp' OR (payload->>'exp')::INT < FLOOR(EXTRACT(EPOCH FROM NOW())) THEN
        RAISE EXCEPTION '%', jsonb_error('Expired signature');
    END IF;
    RETURN payload;
END
$function$;