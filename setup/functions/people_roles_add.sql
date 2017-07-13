-- FIXME: move all exception handling to general function (e.g. data_merge, but then for $ref and double posting function)
CREATE OR REPLACE FUNCTION public.people_roles_add(token TEXT, people_id INT, data JSONB)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    rights payload_permissions;
    _data ALIAS FOR data;
    _people_id ALIAS FOR people_id;
    _roles_id INT;
BEGIN
    rights = permissions_get(token);

    --BEGIN make DRY: if the fucking keys exists is done in data_merge (but not if create: {} / * ... for admin), how do we check for required fields?
    IF data ? 'people_id' THEN
        IF (data->>'people_id')::INT != _people_id THEN
            RAISE EXCEPTION '%', jsonb_error('People id %s in call not equal to id %s in data', _people_id::TEXT, data->>'people_id');
        END IF;
    ELSE
        data = JSONB_SET(data, ARRAY['people_id'], TO_JSON(_people_id)::JSONB);
    END IF;
    IF data ? '$ref' THEN
        _roles_id = SUBSTRING(data->>'$ref', E'^/roles/(\\d+)$')::INT;
        IF _roles_id IS NULL THEN
            RAISE EXCEPTION '%', jsonb_error('Reference "%s" not a valid roles reference', data->>'$ref');
        END IF;
        IF data ? 'roles_id' THEN
            IF (data->>'roles_id')::INT != _roles_id THEN
                RAISE EXCEPTION '%', jsonb_error('Roles id %s in call not equal to id %s in data', _roles_id, data->>'roles_id');
            END IF;
        ELSE
            data = JSONB_SET(data, ARRAY['roles_id'], TO_JSON(_roles_id)::JSONB);
        END IF;
    ELSEIF NOT data ? 'roles_id' THEN
        RAISE EXCEPTION '%', jsonb_error('Must supply reference to a roles id or a direct roles id in data');
    ELSE
        _roles_id = (data->>'roles_id')::INT;
    END IF;
    --END make DRY

    _data = remove_base(data_merge(
        rights := rights,
        ref_table := 'people_roles',
        --base := people_get(rights, people_id)->'people'->people_id::TEXT,
        update := _data - '$ref'
    ));

    --BEGIN make DRY: 
    PERFORM FROM people_roles pr WHERE valid_till IS NULL AND pr.people_id = _people_id AND roles_id = _roles_id;
    IF FOUND THEN
        RAISE EXCEPTION '%', jsonb_error('Relation already exist');
    END IF;
    --END make DRY

    --BEGIN make DRY: 
    PERFORM FROM people p WHERE valid_till IS NULL AND p.id = _people_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_error('People id %s does not exist', _people_id);
    END IF;
    PERFORM FROM roles r WHERE valid_till IS NULL AND r.id = _roles_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_error('Roles id %s does not exist', _roles_id);
    END IF;
    --END make DRY

    INSERT INTO people_roles (people_id, roles_id, modified_by, data)
        VALUES (_people_id, _roles_id, (rights.payload->>'user')::INT, _data - 'people_id' - 'roles_id');

    RETURN people_get(rights, people_id);
END;
$function$;