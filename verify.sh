#!/bin/sh
# verify.sh — the README says "Verified against dig +short on several names and
# two resolvers". This is that sentence, as a program.
#
#   MERE=/path/to/mere-checkout sh verify.sh
#
# ⚠ WHY IT EXISTS. The claim lived in the README and nowhere else: one commit,
# one file, no script. A sentence saying a thing was checked is not the check,
# and nobody -- the author included -- can tell them apart afterwards.
#
# ⚠ WHY THIS ONE IS NOT IN CI. The oracle is the real DNS, so the answers move:
# a name can rotate its A records between two queries a second apart, and a
# resolver can hand two clients different sets. Pinning them would make the
# gate lie within a week. So the comparison is SET equality against a dig run
# taken at the same moment, with one retry -- and when the network or dig is
# missing this FAILS rather than skipping, because "could not check" and
# "checked" must not print the same thing.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
MERE_ROOT="${MERE:-}"
[ -n "$MERE_ROOT" ] || { echo "usage: MERE=/path/to/mere-checkout sh verify.sh" >&2; exit 2; }
M="$MERE_ROOT/_build/default/bin/mere.exe"
[ -x "$M" ] || { echo "verify: $M not found (dune build?)" >&2; exit 2; }
command -v dig >/dev/null 2>&1 || {
  echo "verify: dig absent — the oracle is missing, so nothing here is checked" >&2; exit 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

# mdns needs a real socket, so it only runs compiled -- the interpreter has no
# mock for `udp_open` and says so.
"$M" -c "$DIR/mdns.mere" > "$tmp/md.c" 2>"$tmp/err" || {
  echo "verify: mere -c failed — $(head -1 "$tmp/err")" >&2; exit 1; }
"${CC:-cc}" -O1 -w "$tmp/md.c" -o "$tmp/mdns" 2>>"$tmp/err" || {
  echo "verify: the emitted C did not compile — $(tail -3 "$tmp/err")" >&2; exit 1; }

ours()   { "$tmp/mdns" "$1" "$2" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' | sort -u; }
theirs() { dig +short +time=3 +tries=1 A "$1" "@$2" 2>/dev/null \
             | grep -E '^[0-9]+(\.[0-9]+){3}$' | sort -u; }

NAMES="${MDNS_NAMES-example.com github.com merelang.org}"
RESOLVERS="${MDNS_RESOLVERS-8.8.8.8 1.1.1.1}"

checked=0; fails=0
for n in $NAMES; do
  for r in $RESOLVERS; do
    theirs "$n" "$r" > "$tmp/want"
    if [ ! -s "$tmp/want" ]; then
      echo "FAIL  $n @$r: dig answered nothing — no network, or the name is gone."
      echo "      This is not a skip: the check did not happen."
      fails=$((fails + 1)); continue
    fi
    ours "$n" "$r" > "$tmp/got"
    if ! diff -q "$tmp/want" "$tmp/got" >/dev/null 2>&1; then
      # One retry, because a rotating record set is a legitimate difference
      # between two queries and not a bug in the parser.
      sleep 1; theirs "$n" "$r" > "$tmp/want"; ours "$n" "$r" > "$tmp/got"
    fi
    checked=$((checked + 1))
    if diff -u "$tmp/want" "$tmp/got" > "$tmp/d" 2>&1; then
      echo "PASS  $n @$r: $(wc -l < "$tmp/got" | tr -d ' ') A record(s) match dig"
    else
      echo "FAIL  $n @$r: differs from dig"
      sed 's/^/      /' "$tmp/d"
      fails=$((fails + 1))
    fi
  done
done

# ⚠ A FLOOR. With an empty NAMES list every loop above would be skipped and the
# summary would say ok, which is the failure this file is about.
[ "$checked" -ge 4 ] || {
  echo "verify: only $checked (name, resolver) pairs were checked, expected at least 4" >&2
  exit 1; }

# POISON: the comparison must be able to see a wrong quad.
sed '1s/^[0-9]/9/' "$tmp/want" > "$tmp/poisoned"
if diff -q "$tmp/poisoned" "$tmp/got" >/dev/null 2>&1; then
  echo "FAIL  poison: one address was changed and the comparison did not notice"
  fails=$((fails + 1))
else
  echo "PASS  poison: a changed address is caught"
fi

[ "$fails" -eq 0 ] && { echo "verify: ok ($checked name/resolver pairs, oracle dig)"; exit 0; }
echo "verify: $fails failed"; exit 1
