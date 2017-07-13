--FIXME: refactor and split to multiple functions, 116 lines of pl/pgsql is too much ;)
CREATE OR REPLACE FUNCTION public.data_merge(rights payload_permissions, ref_table VARCHAR, base JSONB = '{}'::JSONB, update JSONB = '{}'::JSONB, remove_fields TEXT[] DEFAULT NULL, remove BOOL DEFAULT FALSE)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
DECLARE
    kv record;
    viewfields JSONB;
    editfields JSONB;
    createfields JSONB;
    changed BOOL;
    remove_field VARCHAR;
BEGIN
    --OK construct: this construct is chosen because a IF NOT(NULL) => NULL,
    -- since we resolve quite some JSONB paths (which resolves to NULL if the key/path doesn't exist)
    -- this IF OK ELSE ERROR construct is way less verbose than checking explicitly for NULL or key exists.
    changed = FALSE;
    viewfields = rights.permissions->ref_table->'view';
    editfields = rights.permissions->ref_table->'edit';
    createfields = rights.permissions->ref_table->'create';
    IF ref_table = 'people' AND (base->>'id')::INT = (rights.payload->>'user')::INT THEN
        viewfields = COALESCE(viewfields, '[]'::JSONB) || COALESCE(rights.permissions->ref_table->'self'->'view', '[]'::JSONB);
        editfields = COALESCE(editfields, '[]'::JSONB) || COALESCE(rights.permissions->ref_table->'self'->'edit', '[]'::JSONB);
    END IF;
    IF base = '{}'::JSONB THEN
        IF rights.permissions->ref_table ? 'create' THEN
            --OK construct
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Creating "%s" not allowed', ref_table);
            RETURN NULL;
        END IF;
    ELSE
        IF base->>'gid' = update->>'gid' THEN
            --OK construct
        ELSEIF base->>'gid' != update->>'gid' THEN
            RAISE EXCEPTION '%', jsonb_error('Outdated gid %s, expected current gid %s', update->>'gid', base->>'gid');
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Must supply gid on update');
        END IF;
    END IF;
    IF remove THEN
        IF rights.permissions->ref_table ? 'create' THEN
            --OK construct
            FOR kv IN (SELECT * FROM JSONB_EACH(createfields))
            LOOP
                IF createfields->kv.key = '*' OR base ? kv.key AND base->kv.key @> kv.value THEN
                    --OK construct
                ELSE
                    RAISE EXCEPTION '%', jsonb_error('Removing "%s" value %s not allowed', kv.key, kv.value::TEXT);
                END IF;
            END LOOP;
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Removing "%s" not allowed', ref_table);
        END IF;
    END IF;
    IF remove_fields IS NULL THEN
        remove_fields = ARRAY[]::TEXT[];
    END IF;
    FOREACH remove_field IN ARRAY remove_fields
    LOOP
        IF rights.permissions->ref_table->'edit' ? remove_field THEN
            --OK construct
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Removing "%s" not allowed', remove_field);
            RETURN NULL;
        END IF;
        IF NOT update ? remove_field THEN
            --OK construct
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Removing and updating "%s" is not allowed (doing both is ambiguous)', remove_field);
            RETURN NULL;
        END IF;
        IF base ? remove_field THEN
            --OK construct
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Removing "%s" not allowed (not present)', remove_field);
            RETURN NULL;
        END IF;
        changed = TRUE;
    END LOOP;
    FOR kv IN (SELECT * FROM JSONB_EACH(update))
    LOOP
        IF editfields ? kv.key THEN
            --OK construct
            IF viewfields ? kv.key THEN
                IF base->kv.key = kv.value THEN
                    --OK construct / nothing changed
                ELSE
                    changed = TRUE;
                END IF;
            ELSE
                changed = TRUE;
            END IF;
        ELSEIF viewfields ? kv.key AND base->kv.key = kv.value THEN
            --OK construct
        ELSEIF base = '{}'::JSONB THEN
            IF createfields ? kv.key THEN
                IF createfields->>kv.key = '*' OR createfields->kv.key @> kv.value THEN
                    --OK construct
                ELSE
                    RAISE EXCEPTION '%', jsonb_error('Creating "%s" with value %s is not allowed', kv.key, kv.value::TEXT);
                END IF;
            ELSE
                RAISE EXCEPTION '%', jsonb_error('Creating "%s" is not allowed', kv.key);
            END IF;
        ELSE
            RAISE EXCEPTION '%', jsonb_error('Editing "%s" is not allowed', kv.key);
        END IF;
    END LOOP;
    IF NOT remove AND base != '{}'::JSONB AND NOT changed THEN
        RAISE EXCEPTION '%', jsonb_error('Editing nothing is not allowed');
    ELSEIF NOT remove AND update = '{}'::JSONB THEN
        RAISE EXCEPTION '%', jsonb_error('Creating nothing is not allowed');
    END IF;
    RETURN remove_fields(base, remove_fields) || update;
END;
$function$;