 #!/bin/awk
{print $0}
BEGIN {create = 0; funct = 0; functname = 0; }
match($0, /(^|\s+)CREATE(\s+.*)?$/, m)   && create == 0 { create=1; $0 = m[2]; }
match($0, /(^|\s+)FUNCTION(\s+.*)?$/, m) && create == 1 && funct == 0 { funct=1; print 2, m[2]; $0 = m[2];}
match($0, /^\s*([^(]+)(.*)$/, m) && create == 1 && funct == 1 && functname == 0 { functname=m[1]; $0 = m[2];}
match($0, /^\s*((IN|OUT|INOUT|VARIADIC)\s+)? ([^(]+)([),])$/, m) && create == 1 && funct == 1 && functname != 0 { $0 = m[2];}
decl == 1 && $0 ~ tagz { decl=0; create=0; funct=0; print 5;}
funct == 1 && /(^AS |\s+AS )([\w$]+)/ {decl=1; tagz=$2; gsub(/\$/,"\\$",tagz); print 3, $2, tagz}
decl == 1 { print 4}

#[ argmode ] [ argname ] argtype [ { DEFAULT | = } default_expr ]