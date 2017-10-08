CREATE OR REPLACE FUNCTION public.to_date(stamp TIMESTAMPTZ)
 RETURNS VARCHAR
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    RETURN TO_CHAR(stamp, 'YYYY-MM-DD"T"HH24:MI:SS.MSOF":00"');
END
$function$;