CREATE OR REPLACE FUNCTION public.roles_set(token TEXT, roles_id INT, data JSONB, remove_fields TEXT[] DEFAULT NULL)
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
        ref_table := 'roles',
        base := roles_get(rights, roles_id, false)->'roles'->roles_id::TEXT,
        update := _data,
        remove_fields := remove_fields
    ));

    UPDATE roles SET valid_till = NOW() WHERE id = roles_id AND valid_till IS NULL;

    INSERT INTO roles (id, valid_from, name, modified_by, data)
        SELECT id, valid_till, _data->>'name', (rights.payload->>'user')::INT, _data -'name'
            FROM roles WHERE id = roles_id ORDER BY valid_till DESC LIMIT 1;

    RETURN roles_get(rights, roles_id);
END;
$function$;