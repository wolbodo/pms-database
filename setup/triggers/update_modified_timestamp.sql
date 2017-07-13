CREATE OR REPLACE FUNCTION public.update_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
	NEW.modified = NOW();
	RETURN NEW;
END;
$function$;

CREATE TRIGGER fields_modified
    BEFORE UPDATE ON fields
    FOR EACH ROW
    EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER jobs_modified
    BEFORE UPDATE ON jobs
    FOR EACH ROW
    EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER people_modified
    BEFORE UPDATE ON people
    FOR EACH ROW
    EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER permissions_modified
    BEFORE UPDATE ON permissions
    FOR EACH ROW
    EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER roles_modified
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER people_roles_modified
    BEFORE UPDATE ON people_roles
    FOR EACH ROW
    EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER roles_permissions_modified
    BEFORE UPDATE ON roles_permissions
    FOR EACH ROW
    EXECUTE PROCEDURE update_timestamp();
