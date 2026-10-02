# ABOUTME: The emission is spelled in the Perl Chalk's own grammar reads back: `use 5.42.0`,
# ABOUTME: `(undef)`, and postfix dereference -- each round-trips and, given a chalk clone, parses.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

# Every emission that rendered, for the chalk parse below.
my @emitted;

sub round_trips ($src, $name, $refuse, $chalk_builds = 1) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
    }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    push @emitted, [$name, $out] if $chalk_builds;
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
    unlike $out, $refuse, "$name: spelled as chalk reads it"
        or diag "--- emitted ---\n$out";
}

# CHALK'S GRAMMAR rejects `use v5.42;` at the `.` -- a two-part v-string --
# and reads `use 5.42.0;`, the spelling of its own lib/. Every one of the
# 130 emitted chalk modules failed to parse on this line alone.
round_trips(<<'SRC', 'the preamble', qr/\Ause v5\.42;/);
print "x\n";
SRC

# `undef()` IS NOT IN CHALK'S GRAMMAR; `undef` and `(undef)` are. The bare
# word cannot stand as an operand -- `undef + 1` is undef(+1) -- so the
# parenthesised form keeps it a term.
round_trips(<<'SRC', 'an undef field default', qr/undef\(\)/);
use v5.42; use experimental 'class';
class C { field $q :param = undef; method q { $q } }
print defined(C->new->q) ? "def\n" : "undef\n";
print C->new(q => 3)->q, "\n";
SRC

round_trips(<<'SRC', 'an undef operand', qr/undef\(\)/);
use v5.42; use experimental 'class';
class C { method pick($n) { my $x = defined($n) ? $n : undef; return defined($x) ? "def" : "undef" } }
print C->new->pick(undef), "\n";
SRC

# CIRCUMFIX DEREFERENCE -- `@{ EXPR }`, `%{ EXPR }` -- is not in chalk's
# grammar at all; `@$name` and postfix `EXPR->@*` are, and the postfix form
# is what chalk's lib/ uses (778 sites, 4 circumfix).
my $circumfix = qr/(?<![\w\$])[\@%]\{/;

# Each program builds its references with `\@x` inside a method, one element
# at a time: chalk's semantic actions at the pinned commit cannot build an
# anonymous `[...]` or `{...}`, nor a list of two elements -- 19 of its own
# originals fail in the same semantic action -- and a test of the spelling
# must not fail on that.
my $box = <<'BOX';
use v5.42; use experimental 'class';
class C {
  method box($a, $b) { my @x = ($a); push(@x, $b); return \@x }
BOX

round_trips($box . <<'SRC', 'the count of a dereferenced call', $circumfix);
  method n($a, $b) { return scalar(@{ $self->box($a, $b) }) } }
print C->new->n(1, 2), "\n";
SRC

round_trips($box . <<'SRC', 'the count of a dereferenced element', $circumfix);
  method n($a, $b) { my %h; $h{k} = $self->box($a, $b); return scalar(@{ $h{k} }) } }
print C->new->n(1, 2), "\n";
SRC

# A HASH REFERENCE -- `\%h` as much as `{...}` -- is past chalk's semantic
# actions at the pinned commit, so this one is checked for spelling only.
round_trips($box . <<'SRC', 'the keys of a dereferenced hash', $circumfix, 0);
  method hbox($a, $b) { my %h = ($a, 1, $b, 2); return \%h }
  method ks($a, $b) { my $h = $self->hbox($a, $b); return join(",", sort(keys(%{ $h }))) } }
print C->new->ks("b", "a"), "\n";
SRC

round_trips($box . <<'SRC', 'a push onto a dereferenced array', $circumfix);
  method p($a, $b) { my $r = $self->box($a, $b); push(@{ $r }, $b); return join(" ", @{ $r }) } }
print C->new->p(1, 2), "\n";
SRC

# `$r->@* = (...)` IS A LIST ASSIGN though it opens with `$`; without the
# parentheses `$r->@* = $b, $a, $b` stores one element. Three elements are
# past chalk's semantic actions (see $box), so this is checked for spelling.
round_trips($box . <<'SRC', 'a list assign into a dereferenced array', $circumfix, 0);
  method p($a, $b) { my $r = $self->box($a, $b); @{ $r } = ($b, $a, $b); return join(" ", @{ $r }) } }
print C->new->p(1, 2), "\n";
SRC

# `\$r->@*` IS THE ARRAY'S REFERENCE; `\($r->@*)` would be a list of
# references to its elements.
round_trips($box . <<'SRC', 'a reference to a dereferenced array', $circumfix);
  method p($a, $b) { my $r = $self->box($a, $b); my $q = \@{ $r }; push(@{ $q }, 9); return join(" ", @{ $r }) } }
print C->new->p(1, 2), "\n";
SRC

round_trips($box . <<'SRC', 'a loop over a dereferenced array', $circumfix);
  method s($a, $b) { my $r = $self->box($a, $b); my $s = 0; for my $x (@{ $r }) { $s += $x } return $s } }
print C->new->s(3, 4), "\n";
SRC

round_trips($box . <<'SRC', 'a method count of a dereferenced field', $circumfix);
  field $xs;
  method load($a, $b) { $xs = $self->box($a, $b); return $self }
  method n { return scalar(@{ $xs }) } }
print C->new->load(1, 2)->n, "\n";
SRC

# A COMPUTED PATTERN is interpolated, and `${\ EXPR}` is not in chalk's
# grammar; a variable is. Measured on chalk's Bootstrap/Terminal.pm,
# `$input =~ /\G($pattern)/`. The target stays itself -- `\G` reads ITS pos.
round_trips(<<'SRC', 'a match against a computed pattern', qr/\$\{\\ /);
use v5.42; use experimental 'class';
class C {
  method m($input, $pos, $p) { pos($input) = $pos; if ($input =~ /\G($p)/) { return $1 } return "none" } }
print C->new->m("abcabc", 3, "a|b"), "\n";
print C->new->m("abcabc", 1, "c"), "\n";
print C->new->m("abcabc", 2, "a|b"), "\n";
SRC

# TEXT A PATTERN LITERAL WOULD READ DIFFERENTLY keeps the interpolated
# value: `[ab]` after `$p` would make `$p[ab]` an array element, and a `$` in
# the text would interpolate. Checked for meaning only.
round_trips(<<'SRC', 'a computed pattern whose text extends a variable', qr/(?!)/, 0);
sub m1 { my $s = $_[0]; return ($s =~ ($_[1] . "[ab]")) ? "y" : "n" }
print m1("xb", "x"), m1("xa", "x"), m1("xc", "x"), "\n";
SRC

round_trips(<<'SRC', 'a computed pattern whose text holds a dollar', qr/(?!)/, 0);
sub m1 { my $s = $_[0]; return ($s =~ ("\$s|" . $_[1])) ? "y" : "n" }
print m1("ab", "b"), m1("ab", "q"), m1("s", "q"), "\n";
SRC

# THE PROOF is chalk's own parser, read from the pinned commit the census
# uses; it needs a chalk clone.
SKIP: {
    my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
    my $snap = "$dir/chalk";
    mkdir $snap;
    skip "no chalk clone with 5948f648 at $chalk (set SON_CHALK)", scalar @emitted
        unless system("git -C '$chalk' archive 5948f648 2>/dev/null | tar -x -C '$snap' 2>/dev/null") == 0
            && -f "$snap/t/bootstrap/lib/TestPipeline.pm";
    my @files;
    for my $i (0 .. $#emitted) {
        my $f = "$dir/e$i.pl";
        open my $fh, '>:utf8', $f or die $!; print $fh $emitted[$i][1]; close $fh;
        push @files, $f;
    }
    my $scan = "$dir/scan.pl";
    open my $sh, '>', $scan or die $!;
    print $sh <<'SCAN';
use 5.42.0; use utf8; use lib 'lib'; use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
my $g = Chalk::Bootstrap::BNF::Target::Perl->new->generate(perl_pipeline());
$g =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SoNScan/g;
eval $g; die $@ if $@;
my $grammar = Chalk::Grammar::Perl::SoNScan::grammar();
for my $f (@ARGV) {
    open my $fh, '<:utf8', $f or die $!; local $/; my $src = <$fh>;
    my $p = build_perl_ir_parser($grammar, start => 'Program');
    my $err = ''; my $r;
    { local *STDERR; open STDERR, '>', \$err; $r = eval { $p->parse_value($src) } }
    my ($why) = ($err . ($@ // '')) =~ /(error: [^\n]*|\S[^\n]*)/;
    say defined $r && !$r->is_zero ? "OK" : "FAIL $why";
}
SCAN
    close $sh;
    my @res = split /\n/, qx(cd '$snap' && $^X $scan @files 2>&1);
    for my $i (0 .. $#emitted) {
        is $res[$i] // '(no result)', 'OK', "chalk parses: $emitted[$i][0]"
            or diag $emitted[$i][1];
    }
}

done_testing;
