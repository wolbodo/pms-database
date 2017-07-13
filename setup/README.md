PMS Postgresql database setup
=============================

Remove
------

***Warning***: this will destroy all data:
```
sudo -u postgres psql -X -c "UPDATE pg_database SET datallowconn = FALSE WHERE datname = 'pms';SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'pms';"
sudo -u postgres psql -X -c 'DROP DATABASE pms;'
```
# cat setup/drop/* | sudo -u postgres psql -X

(First) Install
---------------

We use the convinient [pgrebase](https://github.com/oelmekki/pgrebase/), to install (first install [go-lang](https://golang.org/doc/install#install)):
```
go get github.com/oelmekki/pgrebase
```

# Cannot execute CREATE EXTENSION without superuser privileges.
```
sudo -u postgres psql -X -c 'CREATE DATABASE pms WITH OWNER pms;'
sudo -u postgres psql -d pms -X -c 'CREATE EXTENSION pgcrypto;'
cat setup/sequences/* setup/tabletypes/* setup/tables/* setup/indices/* | sudo -u pms psql -X
sudo -u pms DATABASE_URL=' ' PGHOST='/run/postgresql' pgrebase setup/
```
# | sed "s/:'token_sha256_key'/'$(openssl rand -hex 64)'/g"
# | psql -U pms -X


Mock data
---------

```
sudo -u pms psql -X -f mock.sql
```

Notes
-----

* email uses a very lazy email & FQN checking, but it's better to do it lazy than plain wrong (e.g. not supporting xn-- tld's etc.).
* "REFERENCES ref_table_ (id)" cannot be used since id is not UNIQUE (it's unique with "WHERE valid_till IS NULL").
* modified & created are not exposed to the API, they come in handy if you ever manually write SQL (e.g. data migrations), trust me on this one --bwb.

To Do list
----------

Access control, namely users, schemas, databases and (column) permissions:
* change owner to PMS
* remove DROP, remove UPDATE of modified & created (otherwise it defeats the purpose)
* make pmsapi group/user, give only INSERT and UPDATE column valid_till rights
* make pmsworkerqueue groups/users, since NOTIFY's are DB specific, we can create a seperate DB just for this + 2 exposed functions, e.g. fetch(X) + update(X, data)
* remove access of viewing functions who expose the SHA256 HMAC secret (better: move to HMAC secret table)
* limit access to internal functions, including "*_get(rights payload_permissions" functions
* check if RAISE EXCEPTION without RETURN NULL in data_merge are all ok paths or if some returns can be removed.


    --POST/PUT on people/X AND roles/X
    --with only for roles:  { members: [{$ref:"person/Y", "other": "stuff"}] }
    --with only for people: { roles: [{$ref:"groups/Y", "other": "stuff"}] }
    --note: loop over the complete array to delete/insert/update all links
    -- (hopefully we can just loop over functions for insert/update?)

-- /people/X/ref POST = create, PUT = update, DELETE = delete
-- idem for roles, but on roles 2 ref types can be posted?
-- for new fields: check if we ain't double posting this record (valid for people too!)
-- can do this by using unique constraints for people_roles, and on people email (if not NULL!) too, but
-- if the email field is null we have a problem, can we more in a generic way detect double creates? e.g.
-- does a record with the posted information already exist and was created by the same user in the last 5m?
-- do this by fetching the data+posted data on the ref_table + checking the create + modified_by?


-- general notes: use FOR SHARE on people/roles/permissions?
-- & how are functions/transactions grouped? (FOR SHARE should last complete function, not just the inner function..)
-- http://www.postgresql.org/docs/current/static/explicit-locking.html (use locking functions?)
-- but when is locking really needed??

Use table inheritance?
https://swth.ch/2016/12/03/postgresql-inheritance/