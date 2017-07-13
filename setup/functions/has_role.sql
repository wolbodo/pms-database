CREATE OR REPLACE FUNCTION public.has_role(self_id INT, role_name VARCHAR)
 RETURNS BOOL
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    PERFORM FROM roles r
                JOIN people_roles pr ON (pr.roles_id = r.id OR r.name = 'self') AND pr.valid_till IS NULL AND r.valid_till IS NULL
                JOIN people p ON pr.people_id = p.id AND r.name != 'self' AND p.valid_till IS NULL
            WHERE p.id = self_id AND r.name = role_name;
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    RETURN TRUE;
END;
$function$;