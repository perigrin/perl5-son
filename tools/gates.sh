#!/bin/bash
# ABOUTME: Runs every gate of the wire v2 plan over a snapshot of this repository and of
# ABOUTME: chalk, resumably, and prints one line per gate; exits non-zero on any miss.
#
#   tools/gates.sh [--chalk DIR] [--out DIR] [--jobs N] [--only GATE[,GATE...]]
#   tools/gates.sh --summary --out DIR      what a run has so far (it may still be going)
#   tools/gates.sh --list                   the gates and their limits
#
# IN THE BACKGROUND: nohup tools/gates.sh --out DIR > DIR.log 2>&1 &
#
# WHAT IS RUN. Both working trees are copied (tracked and untracked files, not
# ignored ones) into DIR/snap the first time, and every gate reads the copies:
# an edit made while the gates run cannot reach them
# (docs/memory/run-long-checks-on-a-snapshot.md). chalk's copy is committed
# into a repository of its own, because the census reads chalk through
# `git archive`.
#
# RESUMABLE. A suite keeps one result file per test file, each other gate one
# output file, written when it has finished. Run the same command again after
# a kill or a restart: what finished is not run again. The snapshot is not
# taken again either, so DIR's results are all of one tree. A changed tree
# needs a new DIR.
#
# THE RATCHET GATE ALSO RUNS tools/corpus-roundtrip.pl: the deparser's round
# trip over the corpus, through SoN::Wire::as_v1 (what is left of wire v1; it
# took the place of stage 3's downgrade proof when the v1 writer went, stage
# 6). One gate for both: chalk's t/bootstrap/gates-script.t holds the list.
#
# (STAGE 9b'S PROOF, tools/wire-braun-proof.pl -- each wire equal to the
# stage 9a producer's but for trivial Phis -- ran here once, against 006b485;
# its result is the baseline note's section 15. Retired in stage 10: the 9a
# producer it compares with is history, not a gate.)
#
# THE SUITES LEAVE OUT THREE FILES that are gates of their own, so that none
# runs twice: chalk's t/bootstrap/corpus/son-corpus-wide.t (corpus-gate) and
# t/bootstrap/ir/audit-probes.t (probes), the producer's
# t/wire-verify-ratchet.t (ratchet, here with chalk's lib).
#
# ENVIRONMENT: LLI (default /usr/bin/lli); SON_CHALK (the default for --chalk,
# else ~/dev/chalk); GATES_TEST_TIMEOUT (seconds one test file may take, 5400). PERL5_SON_LIB is set here, to the producer's snapshot,
# and CHALK_WORKLIST_OUT to a file under DIR.
set -u

ROUNDTRIP_MIN=426
DEPARSE_MIN=430
GATE_GREEN_MIN=222
GATES="producer-suite chalk-suite census corpus-gate probes ratchet"

list() {
    cat <<EOF
producer-suite  every t/**/*.t under prove -l: 0 failing files
chalk-suite     every t/**/*.t under prove -Ilib -It/lib: 0 failing files
census          tools/corpus-llvm-roundtrip.pl: ROUNDTRIP >= $ROUNDTRIP_MIN, DIFFERS 0, LLI_FAIL 0
corpus-gate     chalk t/bootstrap/corpus/son-corpus-wide.t: passes, gate-green >= $GATE_GREEN_MIN, paad/worklist.json untouched
probes          chalk tools/audit-probes.pl: WRONG 0, TIMEOUT 0, no probe BASELINE.tsv records SAME is anything else
ratchet         t/wire-verify-ratchet.t over corpus, probes and chalk's lib: no rule broken but by the violations held by name, no fewer wires or graphs than t/data/wire-verify-baseline.tsv, no wire dropped; tools/corpus-roundtrip.pl (the deparser's round trip, through SoN::Wire::as_v1): ROUNDTRIP >= $DEPARSE_MIN, EMITS_INVALID_PERL 0
EOF
}

HERE=$(cd "$(dirname "$0")/.." && pwd)
CHALK=${SON_CHALK:-$HOME/dev/chalk}
OUT=
JOBS=$(nproc 2>/dev/null || echo 2)
ONLY=
SUMMARY=0
while [ $# -gt 0 ]; do
    case $1 in
        --list)    list; exit 0 ;;
        --chalk)   CHALK=$2; shift ;;
        --out)     OUT=$2; shift ;;
        --jobs)    JOBS=$2; shift ;;
        --only)    ONLY=$2; shift ;;
        --summary) SUMMARY=1 ;;
        *) echo "usage: $0 [--chalk DIR] [--out DIR] [--jobs N] [--only GATE,...] [--summary] [--list]" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$OUT" ] || OUT=${TMPDIR:-/tmp}/gates-$(git -C "$HERE" rev-parse --short HEAD 2>/dev/null || echo tree)
[ -n "$ONLY" ] && GATES=$(echo "$ONLY" | tr ',' ' ')
for g in $GATES; do
    list | grep -q "^$g " || { echo "$0: no gate named $g (see --list)" >&2; exit 2; }
done
wanted() { case " $GATES " in *" $1 "*) return 0 ;; esac; return 1; }

P=$OUT/snap/producer
C=$OUT/snap/chalk

# ---------------------------------------------------------------- the summary
# One line per gate: PASS, MISS (it finished and is short of its limit) or
# PEND (not finished). Reads only the files under $OUT.
suite_line() {    # name dir
    local name=$1 d=$OUT/$2 total done fail
    [ -f "$d/all.txt" ] || { printf '%-15s PEND  not started\n' "$name"; return 1; }
    total=$(wc -l < "$d/all.txt")
    done=$(ls "$d/rc" 2>/dev/null | wc -l)
    fail=$(grep -Lx 0 "$d"/rc/* 2>/dev/null | wc -l)
    if [ "$done" -lt "$total" ]; then
        printf '%-15s PEND  %d of %d files, %d failing\n' "$name" "$done" "$total" "$fail"; return 1
    fi
    if [ "$fail" -gt 0 ]; then
        printf '%-15s MISS  %d files, %d failing%s:\n' "$name" "$total" "$fail" "$(secs "$2")"
        for f in $(grep -Lx 0 "$d"/rc/* | head -12); do echo "                  $(basename "$f" | sed 's/__/\//g')"; done
        return 1
    fi
    printf '%-15s PASS  %d files, 0 failing%s\n' "$name" "$total" "$(secs "$2")"
}

census_line() {
    local f=$OUT/census.out
    [ -f "$f" ] || { printf '%-15s PEND\n' census; return 1; }
    local rt df lf gap ld nj
    rt=$(awk '$1=="ROUNDTRIP"{print $2}' "$f"); df=$(awk '$1=="DIFFERS"{print $2}' "$f")
    lf=$(awk '$1=="LLI_FAIL"{print $2}' "$f"); gap=$(awk '$1=="GAP"{print $2}' "$f")
    ld=$(awk '$1=="LOAD_FAIL"{print $2}' "$f"); nj=$(awk '$1=="NOJSON"{print $2}' "$f")
    local v=PASS
    [ "${rt:-0}" -ge $ROUNDTRIP_MIN ] && [ "${df:-1}" -eq 0 ] && [ "${lf:-1}" -eq 0 ] || v=MISS
    printf '%-15s %s  ROUNDTRIP %s (>= %d) DIFFERS %s LLI_FAIL %s; GAP %s LOAD_FAIL %s NOJSON %s%s\n' \
        census $v "${rt:-?}" $ROUNDTRIP_MIN "${df:-?}" "${lf:-?}" "${gap:-?}" "${ld:-?}" "${nj:-?}" "$(secs census)"
    [ $v = PASS ]
}

corpus_gate_line() {
    local f=$OUT/corpus-gate.out
    [ -f "$f" ] || { printf '%-15s PEND\n' corpus-gate; return 1; }
    local gg rc wl v=PASS
    gg=$(grep -o 'TOTAL: gate-green=[0-9]*' "$f" | tail -1 | grep -o '[0-9]*$')
    rc=$(cat "$OUT/corpus-gate.rc")
    wl=$(cat "$OUT/corpus-gate.worklist" 2>/dev/null || echo unknown)
    [ "$rc" -eq 0 ] && [ "${gg:-0}" -ge $GATE_GREEN_MIN ] && [ $wl = untouched ] || v=MISS
    printf '%-15s %s  gate-green %s (>= %d), prove exit %s, paad/worklist.json %s%s\n' \
        corpus-gate $v "${gg:-?}" $GATE_GREEN_MIN "$rc" $wl "$(secs corpus-gate)"
    [ $v = PASS ]
}

probes_line() {
    local f=$OUT/probes.out
    [ -f "$f" ] || { printf '%-15s PEND\n' probes; return 1; }
    local counts wrong timeout lost v=PASS
    counts=$(grep -E '^[A-Z]+=[0-9]+( [A-Z]+=[0-9]+)*$' "$f" | tail -1)
    wrong=$(echo "$counts" | grep -o 'WRONG=[0-9]*' | cut -d= -f2)
    timeout=$(echo "$counts" | grep -o 'TIMEOUT=[0-9]*' | cut -d= -f2)
    lost=$(grep -c '(was SAME)' "$f")
    [ -n "$counts" ] && [ "${wrong:-0}" -eq 0 ] && [ "${timeout:-0}" -eq 0 ] && [ "$lost" -eq 0 ] || v=MISS
    printf '%-15s %s  %s; WRONG %s, SAME lost %s, changed %s%s\n' \
        probes $v "${counts:-no counts}" "${wrong:-0}" "$lost" "$(grep -c '(was ' "$f")" "$(secs probes)"
    [ $v = PASS ] || grep '(was SAME)\|^[a-z0-9]* *WRONG\|^[a-z0-9]* *TIMEOUT' "$f" | head -12 | sed 's/^/                  /'
    [ $v = PASS ]
}

ratchet_line() {
    local f=$OUT/ratchet.out
    [ -f "$f" ] || { printf '%-15s PEND\n' ratchet; return 1; }
    local rc v=PASS chalk
    rc=$(cat "$OUT/ratchet.rc")
    chalk="chalk's lib compared"
    grep -q 'not compared\|chalk lib not checked' "$f" && { chalk="CHALK'S LIB NOT COMPARED ($(grep -o 'chalk is at.*' "$f" | head -1))"; v=MISS; }
    [ "$rc" -eq 0 ] || v=MISS
    printf '%-15s %s  prove exit %s; %s; held by name: %s%s\n' ratchet $v "$rc" "$chalk" "$(grep -c '^# held by name: ' "$f")" "$(secs ratchet)"
    [ $v = PASS ] || grep '^not ok\|^ *not ok' "$f" | head -12 | sed 's/^/                  /'
    [ $v = PASS ]
}

deparse_line() {
    local f=$OUT/deparse.out
    [ -f "$f" ] || { printf '%-15s PEND\n' deparse; return 1; }
    local rt inv v=PASS
    rt=$(awk '$1=="ROUNDTRIP"{print $2}' "$f"); inv=$(awk '$1=="EMITS_INVALID_PERL"{print $2}' "$f")
    [ "${rt:-0}" -ge $DEPARSE_MIN ] && [ "${inv:-1}" -eq 0 ] || v=MISS
    printf '%-15s %s  (deparser round trip) ROUNDTRIP %s (>= %d) EMITS_INVALID_PERL %s%s\n' '' $v "${rt:-?}" $DEPARSE_MIN "${inv:-?}" "$(secs deparse)"
    [ $v = PASS ]
}

# secs(gate) -> " [12m34s]" once the gate has run, else nothing.
secs() {
    local t
    t=$(cat "$OUT/$1.secs" 2>/dev/null) || return 0
    printf ' [%dm%02ds]' $((t / 60)) $((t % 60))
}

summary() {
    local miss=0
    echo "gates: producer $(cat "$OUT/producer.at" 2>/dev/null)  chalk $(cat "$OUT/chalk.at" 2>/dev/null)  ($OUT)"
    wanted producer-suite && { suite_line producer-suite producer-suite || miss=1; }
    wanted chalk-suite    && { suite_line chalk-suite chalk-suite       || miss=1; }
    wanted census         && { census_line      || miss=1; }
    wanted corpus-gate    && { corpus_gate_line || miss=1; }
    wanted probes         && { probes_line      || miss=1; }
    wanted ratchet        && { ratchet_line     || miss=1; }
    wanted ratchet        && { deparse_line     || miss=1; }
    return $miss
}

if [ $SUMMARY = 1 ]; then summary; exit $?; fi

# --------------------------------------------------------------- the snapshot
[ -d "$CHALK/lib/Chalk" ] || { echo "$0: no chalk at $CHALK (--chalk DIR or SON_CHALK)" >&2; exit 2; }
mkdir -p "$OUT/snap" || exit 2

# at(dir) -> "branch sha", with "+uncommitted" when the tree differs from it.
at() {
    local d=$1 s
    s="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null) $(git -C "$d" rev-parse --short=8 HEAD 2>/dev/null)"
    [ -z "$(git -C "$d" status --porcelain 2>/dev/null)" ] || s="$s+uncommitted"
    echo "$s"
}
snap() {    # from to
    mkdir -p "$2.tmp" &&
    ( cd "$1" && git ls-files -co --exclude-standard -z | tar --null -T - -cf - 2>/dev/null ) | tar -xf - -C "$2.tmp" &&
    mv "$2.tmp" "$2"
}
if [ ! -d "$P" ]; then at "$HERE" > "$OUT/producer.at"; snap "$HERE" "$P" || exit 2; fi
if [ ! -d "$C" ]; then
    at "$CHALK" > "$OUT/chalk.at"
    snap "$CHALK" "$C.pre" || exit 2
    ( cd "$C.pre" && git init -q . && git add -A . && git -c user.name=gates -c user.email=gates@localhost commit -q -m snapshot ) || exit 2
    mv "$C.pre" "$C"
fi

export PERL5_SON_LIB=$P/lib
# chalk's corpus gate, and the suite tests that run it, write a worklist:
# here, never into a tree's paad/worklist.json.
export CHALK_WORKLIST_OUT=$OUT/worklist.json
export LLI=${LLI:-/usr/bin/lli}
case ":$PATH:" in *":$(dirname "$LLI"):"*) ;; *) PATH=$(dirname "$LLI"):$PATH ;; esac
ulimit -v 4000000

# ----------------------------------------------------------------- the gates
# one_test(dir, inc, file): prove one file in the current directory; its exit
# status goes to DIR/rc/<file>, its output to DIR/log/<file> when it failed.
one_test() {
    local d=$1 inc=$2 f=$3 key
    key=$(echo "$f" | sed 's/\//__/g')
    [ -f "$d/rc/$key" ] && return 0
    timeout "$TEST_TIMEOUT" prove $inc "$f" > "$d/run.$$.$key" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then mv "$d/run.$$.$key" "$d/log/$key"; else rm -f "$d/run.$$.$key"; fi
    echo $rc > "$d/rc/$key.tmp" && mv "$d/rc/$key.tmp" "$d/rc/$key"
}
export -f one_test
# One test file's limit, in seconds. chalk's t/grammar-conformance.t parses
# every lib module with chalk's own grammar: 40 minutes of one core, more
# beside three other workers. A file that runs out of it fails (exit 124).
export TEST_TIMEOUT=${GATES_TEST_TIMEOUT:-5400}

suite() {    # name tree inc jobs skip-regex
    local d=$OUT/$1
    mkdir -p "$d/rc" "$d/log"
    rm -f "$d"/run.*
    [ -f "$d/all.txt" ] || ( cd "$2" && find t -name '*.t' | sort | grep -Ev "$5" > "$d/all.txt.tmp" && mv "$d/all.txt.tmp" "$d/all.txt" )
    ( cd "$2" && xargs -a "$d/all.txt" -P "$4" -I{} bash -c 'one_test "$@"' _ "$d" "$3" {} )
}

census() {
    [ -f "$OUT/census.out" ] && return 0
    ( cd "$P" && SON_CHALK=$C perl tools/corpus-llvm-roundtrip.pl -v --commit HEAD --jobs "$1" ) > "$OUT/census.tmp" 2>&1
    grep -q '^ROUNDTRIP' "$OUT/census.tmp" && mv "$OUT/census.tmp" "$OUT/census.out"
}

corpus_gate() {
    [ -f "$OUT/corpus-gate.out" ] && return 0
    ( cd "$C" && timeout 3600 prove -Ilib -It/lib t/bootstrap/corpus/son-corpus-wide.t ) > "$OUT/corpus-gate.tmp" 2>&1
    echo $? > "$OUT/corpus-gate.rc"
    # The gate writes its worklist where CHALK_WORKLIST_OUT says; the copy of
    # paad/worklist.json in the snapshot must be as it was committed.
    if ( cd "$C" && git diff --quiet -- paad/worklist.json ); then echo untouched; else echo MODIFIED; fi > "$OUT/corpus-gate.worklist"
    mv "$OUT/corpus-gate.tmp" "$OUT/corpus-gate.out"
}

probes() {
    [ -f "$OUT/probes.out" ] && return 0
    ( cd "$C" && perl -Ilib -It/lib tools/audit-probes.pl --jobs "$1" ) > "$OUT/probes.tmp" 2>&1
    grep -Eq '^[A-Z]+=[0-9]+' "$OUT/probes.tmp" && mv "$OUT/probes.tmp" "$OUT/probes.out"
}

# The wires are kept under $OUT/wires, so a second run verifies without
# compiling again. They are this snapshot's, so the cache cannot go stale.
ratchet() {
    [ -f "$OUT/ratchet.out" ] && return 0
    local sha
    sha=$(awk '{print $2}' "$OUT/chalk.at")
    ( cd "$P" && SON_RATCHET=1 SON_CHALK=$C SON_CHALK_AT=$sha SON_WIRE_CACHE=$OUT/wires SON_WIRE_JOBS=$1 \
        timeout 7200 prove -lv t/wire-verify-ratchet.t ) > "$OUT/ratchet.tmp" 2>&1
    echo $? > "$OUT/ratchet.rc"
    mv "$OUT/ratchet.tmp" "$OUT/ratchet.out"
}

deparse() {
    [ -f "$OUT/deparse.out" ] && return 0
    ( cd "$P" && timeout 3600 perl tools/corpus-roundtrip.pl ) > "$OUT/deparse.tmp" 2>&1
    grep -q '^ROUNDTRIP' "$OUT/deparse.tmp" && mv "$OUT/deparse.tmp" "$OUT/deparse.out"
}

# timed(gate, command...): run it, and add its seconds to $OUT/GATE.secs (a
# resumed gate adds to what it had; a gate with nothing left to do adds 0).
timed() {
    local g=$1 t0=$SECONDS was
    shift
    "$@"
    was=$(cat "$OUT/$g.secs" 2>/dev/null || echo 0)
    echo $((was + SECONDS - t0)) > "$OUT/$g.secs"
}

# The corpus gate (one process) and the ratchet (two) run beside the suites,
# which take every job: for their first minutes the machine is asked for
# three more than it has, and after that for exactly what it has.
bg=""
if wanted corpus-gate; then timed corpus-gate corpus_gate & bg="$bg $!"; fi
if wanted ratchet;     then { timed ratchet ratchet 2; timed deparse deparse; } & bg="$bg $!"; fi
sj=$JOBS
wanted producer-suite && timed producer-suite suite producer-suite "$P" -l "$sj" '^t/wire-verify-ratchet\.t$'
wanted chalk-suite    && timed chalk-suite suite chalk-suite "$C" '-Ilib -It/lib' "$sj" '^t/bootstrap/(corpus/son-corpus-wide|ir/audit-probes)\.t$'
wanted census         && timed census census "$sj"
wanted probes         && timed probes probes "$sj"
[ -z "$bg" ] || wait $bg

summary
