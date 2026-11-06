#!/usr/bin/env bash
# usage: int-repro.sh <timeout-binary>
T="${1:-timeout}"; D="$(mktemp -d)"
cat > "$D/gen" <<'G'
#!/usr/bin/env bash
L="$RLOG"; t() { printf '%s %s\n' "$(date +%s.%N)" "$*" >> "$L"; }
f() {
  local sig="" rc=0 pid
  trap 'sig=INT; t "trap INT ran in BASHPID=$BASHPID"' INT
  trap 'sig=TERM' TERM
  "$RT" -k 5 30 bash -c 'sleep 20' </dev/null >/dev/null 2>&1 &
  pid=$!
  t "started timeout pid=$pid in BASHPID=$BASHPID"
  wait "$pid" || rc=$?
  t "wait returned rc=$rc sig=$sig"
  if [ -n "$sig" ]; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null; t "second wait rc=$?"
    trap - INT TERM
    t "re-raising $sig on $BASHPID"
    kill -s "$sig" "$BASHPID"
    t "STILL ALIVE after re-raise"
  fi
}
X="$(f)" || true
t "generator continued after subst (rc=$?)"
G
chmod +x "$D/gen"
printf '%s\n' '#!/usr/bin/env bash' 'echo $$ > "$RPG"' "trap ':' INT" '"$@"' 'echo $? > "$RRCF"' > "$D/run"; chmod +x "$D/run"
t0=$(date +%s)
( cd "$D" && RT="$T" RLOG="$D/log" RPG="$D/pg" RRCF="$D/rcf" setsid "$D/run" "$D/gen" & )
for _ in $(seq 1 50); do [[ -s "$D/pg" ]] && break; sleep 0.1; done
sleep 1.5
ps -o pid,pgid,stat,comm,args -g "$(cat "$D/pg")" || true
grep -E '^Sig(Ign|Cgt|Blk)' /proc/"$(pgrep -g "$(cat "$D/pg")" -x timeout -n 2>/dev/null || pgrep -x gnutimeout -n)"/status 2>/dev/null || true
printf '%s sending INT to -%s\n' "$(date +%s.%N)" "$(cat "$D/pg")" >> "$D/log"
kill -INT -- "-$(cat "$D/pg")"
for _ in $(seq 1 300); do [[ -s "$D/rcf" ]] && break; sleep 0.1; done
echo "== $T: rc=$(cat "$D/rcf" 2>/dev/null) secs=$(( $(date +%s) - t0 ))"; cat "$D/log"
