CREATE OR REPLACE FUNCTION public.people_history(rights payload_permissions, people_id INT)
 RETURNS JSONB
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    _people_id ALIAS FOR people_id;
    viewfields JSONB;
    history JSONB;
BEGIN
    viewfields = rights.permissions->'people'->'view';
    IF _people_id = (rights.payload->>'user')::INT THEN
        viewfields = COALESCE(viewfields, '[]'::JSONB) || COALESCE(rights.permissions->'people'->'self'->'view', '[]'::JSONB);
    END IF;
    SELECT JSONB_BUILD_OBJECT('history', JSONB_BUILD_OBJECT('people', JSONB_BUILD_OBJECT(_people_id::TEXT, JSONB_AGG(obj)))) INTO history
    FROM (
        SELECT DISTINCT ON (FIRST_VALUE(gid) OVER w) JSONB_BUILD_OBJECT(
                'gid', TO_JSON(FIRST_VALUE(gid) OVER w)::JSONB,
                'id', TO_JSON(FIRST_VALUE(id) OVER w)::JSONB,
                'valid_from', to_date(LAST_VALUE(valid_from) OVER w),
                'valid_till', to_date(FIRST_VALUE(valid_till) OVER w),
                'modified_by', LAST_VALUE(modified_by) OVER w
            )
            || LAST_VALUE(object) OVER w AS obj
            --JSONB_SET(
            --    LAST_VALUE(object) OVER w,
            --    ARRAY['record', 'gid'],
            --    FIRST_VALUE(gid) OVER w::TEXT::JSONB
            --) AS obj
        FROM (
            SELECT gid, id, valid_from, valid_till, modified_by, object,
                ROW_NUMBER() OVER (ORDER BY valid_from DESC) - ROW_NUMBER() OVER (PARTITION BY object->'record' ORDER BY valid_from DESC) AS grouping
            FROM (
                SELECT gid, id, valid_from, valid_till, modified_by, (
                    SELECT JSONB_BUILD_OBJECT('record', JSONB_OBJECT_AGG(base.key, base.value) FILTER (WHERE base.key IS NOT NULL))
                        || JSONB_STRIP_NULLS(JSONB_BUILD_OBJECT(
                            'added', JSONB_OBJECT_AGG(base.key, base.value) FILTER (WHERE lastdata.key IS NULL),
                            'updated', JSONB_OBJECT_AGG(base.key, lastdata.value) FILTER (WHERE lastdata.key IS NOT NULL AND base.value != lastdata.value),
                            'removed', JSONB_OBJECT_AGG(lastdata.key, lastdata.value) FILTER (WHERE base.key IS NULL)
                        ))
                    FROM JSONB_EACH(data) base
                    FULL OUTER JOIN JSONB_EACH(lastdata) lastdata ON base.key = lastdata.key
                    WHERE
                        viewfields ? base.key OR viewfields ? lastdata.key
                ) AS object
                FROM (SELECT gid, id, valid_from, valid_till, modified_by, data || JSONB_BUILD_OBJECT('email', email, 'phone', phone) AS data,
                    LEAD(data) OVER chrono || JSONB_BUILD_OBJECT('email', LEAD(email) OVER chrono, 'phone', LEAD(phone) OVER chrono) AS lastdata
                    FROM people WHERE id = _people_id WINDOW chrono AS (ORDER BY valid_from DESC) ORDER BY valid_from DESC) alias
            ) alias
            ORDER BY valid_from DESC
        ) alias
        WINDOW w AS (PARTITION BY grouping, object->'record' ORDER BY valid_from DESC
            range between unbounded preceding and unbounded following)
        ORDER BY FIRST_VALUE(gid) OVER w DESC
    ) alias;
    RETURN history; 
END;
$function$;

CREATE OR REPLACE FUNCTION public.people_history(token TEXT, people_id INT)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN people_history(rights := permissions_get(token), people_id := people_id);
END;
$function$;

----NOTE: Easier, but reporting wrong (old) gids. Could be used / prefered if we skip reporting gids in the history.
--CREATE OR REPLACE FUNCTION public.people_history(rights payload_permissions, people_id INT)
-- RETURNS JSONB
-- LANGUAGE plpgsql
--AS $function$
--DECLARE
--    _people_id ALIAS FOR people_id;
--    viewfields JSONB;
--    history JSONB;
--BEGIN
--    viewfields = rights.permissions->'people'->'view';
--    IF _people_id = (rights.payload->>'user')::INT THEN
--        viewfields = COALESCE(viewfields, '[]'::JSONB) || COALESCE(rights.permissions->'people'->'self'->'view', '[]'::JSONB);
--    END IF;
--    SELECT JSONB_BUILD_OBJECT('history', JSONB_BUILD_OBJECT('people', JSONB_BUILD_OBJECT(_people_id::TEXT, JSONB_AGG(obj)))) INTO history
--    FROM (
--        SELECT JSONB_BUILD_OBJECT(
--            --'gid', gid,
--            'valid_from', to_date(COALESCE(lead(valid_till) OVER w, valid_from)),
--            'valid_till', to_date(lag(valid_from) OVER w),
--            'modified_by', modified_by
--        ) || object AS obj
--        FROM (
--            SELECT gid, id, valid_from, valid_till, modified_by, (
--                SELECT JSONB_BUILD_OBJECT('record', JSONB_OBJECT_AGG(base.key, base.value) FILTER (WHERE base.key IS NOT NULL))
--                    || JSONB_STRIP_NULLS(JSONB_BUILD_OBJECT(
--                        'added', JSONB_OBJECT_AGG(base.key, base.value) FILTER (WHERE lastdata.key IS NULL),
--                        'updated', JSONB_OBJECT_AGG(base.key, lastdata.value) FILTER (WHERE lastdata.key IS NOT NULL AND base.value != lastdata.value),
--                        'removed', JSONB_OBJECT_AGG(lastdata.key, lastdata.value) FILTER (WHERE base.key IS NULL)
--                    ))
--                FROM JSONB_EACH(data) base
--                FULL OUTER JOIN JSONB_EACH(lastdata) lastdata ON base.key = lastdata.key
--                WHERE
--                    viewfields ? base.key OR viewfields ? lastdata.key
--            ) AS object
--            FROM (SELECT gid, id, valid_from, valid_till, modified_by, data || JSONB_BUILD_OBJECT('email', email, 'phone', phone) AS data,
--                LEAD(data) OVER chrono || JSONB_BUILD_OBJECT('email', LEAD(email) OVER chrono, 'phone', LEAD(phone) OVER chrono) AS lastdata
--                FROM people WHERE id = _people_id WINDOW chrono AS (ORDER BY valid_from DESC) ORDER BY valid_from DESC) alias
--        ) alias
--        WHERE object ?| array['added', 'updated', 'removed']
--        WINDOW w AS (ORDER BY valid_from DESC)
--        ORDER BY valid_from DESC
--    ) alias;
--    RETURN history; 
--END;
--$function$;