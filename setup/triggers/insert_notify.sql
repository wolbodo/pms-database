CREATE OR REPLACE FUNCTION public.insert_notify(channel TEXT, type TEXT)
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM pg_notify(channel, JSON_BUILD_OBJECT('gid', NEW.gid, 'type', type)::TEXT);
END;
$function$;

CREATE TRIGGER jobs_insert_trigger
    AFTER INSERT ON jobs
    WHEN (NEW.type = 'email')
    EXECUTE PROCEDURE insert_notify('jobs', 'email');
