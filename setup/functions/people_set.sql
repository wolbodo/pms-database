CREATE OR REPLACE FUNCTION public.people_set(token TEXT, people_id INT, data JSONB, remove_fields TEXT[] DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
    _data ALIAS FOR data;
BEGIN
    rights = permissions_get(token);
    _data = remove_base(data_merge(
        rights := rights,
        ref_table := 'people',
        base := people_get(rights, people_id, false)->'people'->people_id::TEXT,
        update := _data,
        remove_fields := remove_fields
    ));

    UPDATE people SET valid_till = NOW() WHERE id = people_id AND valid_till IS NULL;

    INSERT INTO people (id, valid_from, email, phone, password_hash, modified_by, data)
        SELECT id, valid_till, _data->>'email', _data->>'phone', password_hash, (rights.payload->>'user')::INT, _data -'email' -'phone'
            FROM people WHERE id = people_id ORDER BY valid_till DESC LIMIT 1;

    RETURN people_get(rights, people_id);
END;
$function$;