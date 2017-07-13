SELECT * FROM pg_catalog.pg_extension;

SELECT * FROM pg_catalog.pg_user;

SELECT d.*, p.proname FROM   pg_depend d LEFT JOIN pg_catalog.pg_proc p ON d.objid = p.oid WHERE deptype = 'e' ORDER BY 1;

optimum step:
V 1 import csv log to DB & clear csv log
V 3 find all function(and type?) signatures
V 4 gather all 
V 5 compare check datetime of log
6 create 'call signature'
7 lookup signature
8 check if return types are the same
9 if not: drop

can we do an alias trick? does it exists in pg_type?

rewrite alias types: https://www.postgresql.org/docs/current/static/datatype.html#DATATYPE-TABLE

bonus: sed to /CREATE FUNCTION/CREATE OR REPLACE FUNCTION/g ?

0) use \gset instead of piping to psql (not working, note [required?] newline)

1) split arguments (cannot split on ',' because of DEFAULT ?)
2) ignore OUT arguments (fuck this detection)
3) ignore DEFAULT part
4) lookup lastpart + fullpart (for 'timestamp with time zone') to oid
5) check if current oid vector has a different return type
6) if so drop!

7) what about arrays??? (the ',', also if there is a , in DEFAULT string, jsonb, or array)


sed: read FUNCTION on a line .. capture untill AS (XXX) .. skip/delete untill XXX; see dollar quoted strings ($tag$)
https://www.postgresql.org/docs/current/static/sql-syntax-lexical.html#SQL-SYNTAX-DOLLAR-QUOTING

awk ' {print $0} create != 1 && /CREATE/ { create=1; print 1; } /FUNCTION/ && create==1 && funct != 1 { funct=1; print 2;} decl==1 && $0 ~ tagz { decl=0;create=0;funct=0;print 5;} funct==1 && /(^AS |\s+AS )([\w$]+)/{decl=1;tagz=$2;gsub(/\$/,"\\$",tagz);print 3, $2, tagz} decl == 1 { print 4} ' setup/functions/people_get.sql; echo



#add signature check on create, since it might need a drop (if the return type differs), also needed in inotify
#ERROR:  cannot change return type of existing function
#HINT:  Use DROP FUNCTION f1(integer) first.
# only happens on exact same (call) signature, not on all overloading
#better do a while loop on the files instaed of -R grep or *.sql .. since we need to stat anyway...

grep -Pzoi '\s+FUNCTION\s+[\w_\.]+\s*\(.*\)\s+RETURNS\s+[\w_\[\]]+\s+' functions/*.sql
| awk split filename & function names

grep -Pizo 'FUNCTION\s+[\w\._]+\s*\(.*\)\s+RETURNS\s+\w+\s+' setup/functions/jsonb_base64url.sql | tr '\n' ' ' | sed -r 's/FUNCTION\s+([a-z0-9\._]+)\s*\(([^\)].*)\)\s+RETURNS\s+([a-z0-9\.]+)\s+/\1; \2; \3\n/ig' | awk -F\; '{print $2}'

psql -E -U pms pms

SELECT * FROM postgres_log

.pgpass ? ENV variables for DB etc.?

inotifywait  -mr --format '%w%f' -e close_write setup/ | while true; do read file; echo "executing $file:";psql -U pms -Xf "$file"; done

SELECT oid, typname, pg_catalog.format_type(oid::OID, NULL) FROM pg_catalog.pg_type WHERE 'timestamptz' IN (typname, pg_catalog.format_type(oid::OID, NULL));

--drop all functions we can drop without cascading (so no triggers or extension functions)
psql -U pms -d pms -Xt <<SQL
SELECT 'SELECT;' || COALESCE(queries,'') AS queries FROM (SELECT 'SELECT;' || string_agg(DISTINCT 'DROP FUNCTION ' || n.nspname || '.' ||  p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ');','') AS queries FROM pg_catalog.pg_proc p LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname NOT IN ('pg_catalog','information_schema') AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE refobjid = p.oid OR (objid = p.oid AND deptype = 'e')) AND pg_catalog.pg_function_is_visible(p.oid)) alias
\gset
:queries
SQL

--now drop all types we can drop without cascading (ignore internal dependencies)
psql -U pms -d pms -Xt <<SQL
SELECT string_agg('DROP TYPE ' || n.nspname || '.' || pg_catalog.format_type(t.oid, NULL) || ';', '') AS queries FROM pg_catalog.pg_type t LEFT JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace WHERE (t.typrelid = 0 OR (SELECT c.relkind = 'c' FROM pg_catalog.pg_class c WHERE c.oid = t.typrelid)) AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_type el WHERE el.oid = t.typelem AND el.typarray = t.oid) AND NOT EXISTS(SELECT 1 FROM pg_depend WHERE refobjid = t.oid AND deptype != 'i') AND n.nspname NOT IN ('pg_catalog','information_schema') AND pg_catalog.pg_type_is_visible(t.oid);
\gset
:queries
SQL

cat setup/types/*.sql setup/functions/*.sql | psql -U pms -X

