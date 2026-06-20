# t1: patterns, fields, arithmetic, control flow, builtins.
# Run as:  awk t1.awk -o t1.exe   then   t1.exe < data
BEGIN { print "report:" }

# accumulate column 2 by the label in column 1
{ total[$1] += $2; n++ }

# a per-line pattern with a relational test
$2 > 100 { big++ }

END {
    print "rows:", n
    for (k in total) printf "  %s = %d\n", k, total[k]
    print "rows over 100:", big
}
