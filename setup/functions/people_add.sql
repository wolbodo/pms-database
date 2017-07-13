CREATE OR REPLACE FUNCTION public.people_add(token TEXT, data JSONB)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
    _data ALIAS FOR data;
    people_id INT;
BEGIN
    rights = permissions_get(token);
    _data = remove_base(data_merge(
        rights := rights,
        ref_table := 'people',
        update := _data
    ));

    INSERT INTO people (email, phone, modified_by, data)
        VALUES (_data->>'email', _data->>'phone', (rights.payload->>'user')::INT, _data -'email' -'phone') RETURNING id INTO people_id;

    RETURN people_get(rights, people_id);
END;
$function$;