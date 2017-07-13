CREATE OR REPLACE FUNCTION public.roles_add(token TEXT, data JSONB)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
    _data ALIAS FOR data;
    roles_id INT;
BEGIN
    rights = permissions_get(token);
    _data = remove_base(data_merge(
        rights := rights,
        ref_table := 'roles',
        update := _data
    ));

    INSERT INTO roles (name, modified_by, data)
        VALUES (_data->>'name', (rights.payload->>'user')::INT, _data -'name') RETURNING id INTO roles_id;

    RETURN roles_get(rights, roles_id);
END;
$function$;