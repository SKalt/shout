#!/bin/sh
cat <<EOF
$0
EOF
echo 'ok' | awk 'BEGIN { print "start" } {
  cmd="echo hello; echo there"
  while (result=(cmd | getline line); result>0) {
    print line
  }
  close(cmd)
  print "result: " result
} END { print "done" }'


