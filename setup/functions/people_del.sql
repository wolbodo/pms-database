CREATE OR REPLACE FUNCTION public.people_del(token TEXT, people_id INT)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
BEGIN
    rights = permissions_get(token);
    PERFORM data_merge(
        rights := rights,
        ref_table := 'people',
        base := people_get(rights, people_id)->'people'->people_id::TEXT,
        remove := TRUE
    );

    UPDATE people SET valid_till = NOW() WHERE id = people_id AND valid_till IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_error('No active person with id=%s found', people_id);
    END IF;
    RETURN 'true'::JSONB;--people_get(rights, people_id);
END;
$function$;