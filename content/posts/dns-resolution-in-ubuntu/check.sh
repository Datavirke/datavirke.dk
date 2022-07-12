#!/bin/bash

# The empty line at the beginning is for 'no search domain'
RESOLVS="
search com
search example.com"

LOOKUP_COMMANDS="nslookup %s
nslookup -search %s
nslookup -search -ndots=2 %s
nslookup -search -ndots=3 %s
host %s
host -N=2 %s
host -N=3 %s
dig %s
dig +search %s
dig +search +ndots=2 %s
dig +search +ndots=3 %s
resolvectl query %s
resolvectl query --search=no %s
resolvectl query --search=yes %s
drill %s"

URLS="example
example.com
www
www.example
www.example.com"

TRUTH_VALUE=$(dig +short example.com @1.1.1.1)

if [ -z "$TRUTH_VALUE" ]; then
  echo "Failed to get real address of example.com"
  exit 1
else
  echo "Using $TRUTH_VALUE as the truth value"
fi

echo "| command | (none) | com | example.com |"
echo "|---------|--------|-----|-------------|"

while read LOOKUP_COMMAND; do
  while read URL; do
    FULL_CMD=$(printf "$LOOKUP_COMMAND" "$URL")
    printf '| `%s` |' "$(printf "$LOOKUP_COMMAND" "$URL" | xargs)"

    while read RESOLV; do
      echo "nameserver 1.1.1.1" > "/etc/resolv.conf"
      echo "$RESOLV" >> "/etc/resolv.conf"
      DEBUG_OUTPUT=$(eval 2>&1 $FULL_CMD)
      resolvectl flush-caches
      if [[ "$DEBUG_OUTPUT" == *"$TRUTH_VALUE"* ]]; then
        printf " ✅ |"
      else
        printf " ❌ |"
      fi
    done <<<$RESOLVS
    printf "\n"
  done <<<$URLS
done <<<$LOOKUP_COMMANDS