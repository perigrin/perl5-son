#!/bin/bash
# ABOUTME: Cloud-session setup for perl5-son: perl 5.42.0, SoN's XS, chalk at the pinned commit, perl's t/.
# ABOUTME: Runs as root from the perl5-son checkout; every path the tools and tests expect is created here.
set -euo pipefail

PREFIX=/home/runner/.local/share/pvm/versions/5.42.0   # the prebuilt perl's RUNPATH and @INC are fixed to this
DEV=/home/perigrin/dev                                  # 4 tests name /home/perigrin/dev/perl5 directly
CHALK_PIN=5948f648                                      # tools/chalk-lib-roundtrip.pl's pinned commit
PERL5_PIN=94e5086608bcf1d01cd2d836f11ca8378a3320b6                              # full SHA: GitHub will not fetch an abbreviated one; the blead commit perl t/ was measured at
REPO=$(pwd)

# perl 5.42.0, prebuilt by pvm. It is not relocatable, so it goes at its own prefix.
mkdir -p "$PREFIX"
curl -fsSL https://github.com/perigrin/pvm/releases/download/perl-5.42.0/perl-5.42.0-linux-amd64.tar.gz \
  | tar -xz -C "$PREFIX"
ln -sf "$PREFIX/bin/perl" /usr/local/bin/perl
ln -sf "$PREFIX/bin/prove" /usr/local/bin/prove
export PATH="$PREFIX/bin:$PATH"
perl -e 'die "wrong perl $^V\n" unless $^V eq v5.42.0'

# cpanfile deps: only YAML::PP is not core; chalk needs nothing beyond core.
# cpanm from CPAN itself. The cloud proxy allows www.cpan.org but not cpanmin.us,
# cpan.metacpan.org or cpanmetadb, so both cpanm and its package index come from there, and
# Debian's cpanm is a wrapper that needs the system perl's libraries. The dist's bin/cpanm
# is fatpacked, so running it with 5.42.0 installs into 5.42.0.
curl -fsSL -o /tmp/cpanm.tgz https://www.cpan.org/authors/id/M/MI/MIYAGAWA/App-cpanminus-1.7047.tar.gz
echo "963e63c6e1a8725ff2f624e9086396ae150db51dd0a337c3781d09a994af05a5  /tmp/cpanm.tgz" | sha256sum -c -
tar -xzOf /tmp/cpanm.tgz App-cpanminus-1.7047/bin/cpanm > /usr/local/bin/cpanm
perl /usr/local/bin/cpanm --no-lwp --mirror https://www.cpan.org --mirror-only --notest YAML::PP Module::Build
perl -MYAML::PP -MModule::Build -e 1   # fails here if cpanm installed into the wrong perl

# SoN's XS (FieldInfo.xs). Tests load SoN.so from site_perl, so it is installed, not left in blib.
command -v cc >/dev/null || { apt-get update -q && apt-get install -yq build-essential; }
perl Makefile.PL && make && make install && make clean

# LLVM 15. chalk's LLVM tests name /usr/lib/llvm-15/bin/lli and skip_all without
# it -- in BOTH of gate 3's trees, so 64 files counted SAME having run nothing.
[ -x /usr/lib/llvm-15/bin/lli ] || { apt-get update -q && apt-get install -yq llvm-15; }
/usr/lib/llvm-15/bin/lli --version >/dev/null

# chalk at the pin, and perl5's t/ at the commit the perl_t census uses. A rerun
# keeps the clones and only re-checks the pins.
mkdir -p "$DEV"
[ -d "$DEV/chalk/.git" ] ||
  git clone -q --branch bson/roundtrip-pin https://github.com/perigrin/chalk.git "$DEV/chalk"
git -C "$DEV/chalk" cat-file -e "$CHALK_PIN^{commit}"
[ -d "$DEV/perl5/.git" ] || {
  git init -q "$DEV/perl5"
  git -C "$DEV/perl5" remote add origin https://github.com/Perl/perl5.git
}
# lib/ too: run from perl5/t, tests put ../lib first in @INC and load its
# strict.pm, warnings.pm and B/Op_private.pm (t/wire-qr-mark-ownership.t).
git -C "$DEV/perl5" sparse-checkout set t lib
git -C "$DEV/perl5" cat-file -e "$PERL5_PIN^{commit}" 2>/dev/null ||
  git -C "$DEV/perl5" fetch -q --depth 1 origin "$PERL5_PIN"
git -C "$DEV/perl5" checkout -q "$PERL5_PIN"

# Plugins do not load in cloud sessions, but a repo's .claude/skills does. Copy each
# plugin's skills in from its public repo; they stay untracked and never reach a commit.
# ponytail: default branches, not the versions installed on shin (superpowers 6.1.1,
# paad 1.11.0, ponytail 4.8.4, i-have-adhd 0.1.0); pin refs if they drift.
fetch_skills () {   # repo-url subdir
  local d; d=$(mktemp -d)
  git clone -q --depth 1 "$1" "$d"
  cp -r "$d/$2"/*/ "$REPO/.claude/skills/"   # directories only: ponytail's has a stray plugin.json
  rm -rf "$d"
}
mkdir -p "$REPO/.claude/skills"
fetch_skills https://github.com/obra/superpowers.git     skills
fetch_skills https://github.com/Ovid/paad.git            plugins/paad/skills
fetch_skills https://github.com/DietrichGebert/ponytail.git skills
fetch_skills https://github.com/ayghri/i-have-adhd.git   skills
grep -qxF '.claude/skills/' "$REPO/.git/info/exclude" || echo '.claude/skills/' >> "$REPO/.git/info/exclude"

# Those plugins inject their rules through SessionStart hooks, which a skill alone does
# not; CLAUDE.local.md (untracked) asks for them on every turn instead.
cat > "$REPO/CLAUDE.local.md" <<'EOF'
# Cloud session rules
- Before any response, load and follow these skills; they apply to every turn: using-superpowers, ponytail (level full), i-have-adhd.
- Use superpowers:test-driven-development for every fix and superpowers:verification-before-completion before any claim of done.
- Read docs/memory/MEMORY.md at the start of the session and open any entry that bears on the task; record new lessons there in the same format.
EOF
grep -qxF 'CLAUDE.local.md' "$REPO/.git/info/exclude" || echo 'CLAUDE.local.md' >> "$REPO/.git/info/exclude"

# Every session user finds the same clones whatever its HOME is.
cat > /etc/profile.d/perl5-son.sh <<EOF
export PATH="$PREFIX/bin:\$PATH"
export SON_CHALK="$DEV/chalk"
export SON_PERL_T="$DEV/perl5/t"
EOF
chmod -R a+rwX "$DEV" "$PREFIX" "$REPO/.claude/skills" "$REPO/CLAUDE.local.md"

echo "setup done: $(perl -v | sed -n 2p); chalk $(git -C "$DEV/chalk" rev-parse --short HEAD); repo $REPO"
