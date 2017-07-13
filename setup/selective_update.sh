#!/bin/bash
echo "importing log";
cat /tmp/postgresql-ddl.csv | psql -U pms -Xc 'COPY postgres_log FROM STDIN WITH csv;' && echo -n '' > /tmp/postgresql-ddl.csv
echo "scanning files and checking for changes"
for FILE in functions/*.sql; do
  LASTMOD=$(stat "$FILE" -c %Y);
  FUNCTIONHEADERS=$(grep -Pzoi 'FUNCTION\s+[\w_\.]+\s*\(.*\)\s+RETURNS\s+[\w_\[\]]+\s+' "$FILE");
  SQLTSMODS=(echo "$FUNCTIONHEADERS" | while read -d '' MATCH; do SQLLIKEFUNC=$(echo "$MATCH" | sed "s/_/\\_/g;s/'/''/g");TS=$(psql -U pms -Xtc "SELECT FLOOR(EXTRACT(EPOCH FROM log_time)) FROM postgres_log WHERE message LIKE 'statement: %CREATE%$SQLLIKEFUNC%' ORDER BY log_time DESC LIMIT 1;");echo "$TS"; done));
  DIRTY=0;
  for TS in "${SQLTSMODS[@]}"; do
    if [ $LASTMOD -gt $TS ]; then
    	DIRTY=1;
    fi
  done;
  if [ $DIRTY = '1' ]; then
  	echo $FILE;
  	SQLTSMODS=($(echo "$FUNCTIONHEADERS" | sed "s/_/\\_/g;s/'/''/g");TS=$(psql -U pms -Xtc "SELECT FLOOR(EXTRACT(EPOCH FROM log_time)) FROM postgres_log WHERE message LIKE 'statement: %CREATE%$SQLLIKEFUNC%' ORDER BY log_time DESC LIMIT 1;");echo "$TS"; done));
  	# check signatures..
  fi
done;