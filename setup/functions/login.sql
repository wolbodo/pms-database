CREATE OR REPLACE FUNCTION public.login(emailaddress TEXT, password TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    token TEXT;
BEGIN
    SELECT
        create_jwt(JSONB_BUILD_OBJECT(
            'user', p.id,
            'exp', FLOOR(EXTRACT(EPOCH FROM NOW() + INTERVAL '31 days'))
        )) INTO STRICT token
        FROM people p
            JOIN people_roles pr ON pr.people_id = p.id AND p.valid_till IS NULL AND pr.valid_till IS NULL
            JOIN roles r ON pr.roles_id = r.id AND r.valid_till IS NULL
        WHERE p.email = emailaddress AND CRYPT(password, p.password_hash) = p.password_hash AND r.name = 'login';
    RETURN JSONB_BUILD_OBJECT(
        'token', token,
        'permissions', (permissions_get(token := token)).permissions
    );
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION '%', jsonb_error('Username or password wrong');
    WHEN TOO_MANY_ROWS THEN
        RAISE EXCEPTION '%', jsonb_error('More than one entry found, please contact an admin or board member to fix this');
END
$function$;