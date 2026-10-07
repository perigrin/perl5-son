# ABOUTME: A statement that conditionally rebinds a lexical -- `$s .= $q if defined $q` --
# ABOUTME: is emitted as a variable and a guarded assignment, not folded into a ternary.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# A POSTFIX `if` THAT ONLY REBINDS A SCALAR was lowered as a value merge --
# right, and spelled as one expression, `defined($q) ? (... . $q) : (...)`,
# with no `if` left in it. chalk's cfg-statements.t parses
# lib/Chalk/Grammar/Symbol.pm with chalk's own parser and asserts an If is
# there; against the emitted module it found none. The producer marks such a
# merge and pins it where the statement stood; the renderer spells it back as
# a guarded assignment.
sub emitted ($src) {
    my $data = graph_of($src) or return;
    return SoN::Deparse->new->render($data);
}

round_trips(<<'SRC', 'a postfix if that appends');
sub show { my ($v, $q) = @_; my $s = "<$v>"; $s .= $q if defined $q; return $s }
print show("a", "+"), show("b"), "\n";
SRC

round_trips(<<'SRC', 'a postfix unless');
sub f { my ($n) = @_; my $r = "pos"; $r = "neg" unless $n > 0; return $r }
print f(1), f(-1), "\n";
SRC

round_trips(<<'SRC', 'a one-armed block if');
sub f { my ($n) = @_; my $r = $n * 2; if ($n > 5) { $r = $r + 100 } return $r }
print f(3), " ", f(9), "\n";
SRC

round_trips(<<'SRC', 'two slots rebound by one statement');
sub f { my ($n) = @_; my ($a, $b) = (1, 2); if ($n) { $a = 10; $b = 20 } return "$a,$b" }
print f(1), " ", f(0), "\n";
SRC

my $out = emitted(<<'SRC') // '';
sub show { my ($v, $q) = @_; my $s = "<$v>"; $s .= $q if defined $q; return $s }
print show("a", "+"), "\n";
SRC
like $out, qr/\bif \(defined\(\$q\)\) \{/,
    'the rebind is spelled as a guarded assignment';
unlike $out, qr/defined\(\$q\) \?/, 'and not as a ternary';

# CHALK'S OWN PARSER finds the If in the emitted Symbol.pm, as
# cfg-statements.t asks of it -- when a chalk clone is present.
SKIP: {
    my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
    skip 'no chalk clone', 1 unless -d "$chalk/.git";
    my $mod = `git -C '$chalk' show 5948f648:lib/Chalk/Grammar/Symbol.pm 2>/dev/null`;
    skip 'no Symbol.pm at 5948f648', 1 unless length $mod;
    my $src = emitted($mod) // '';
    like $src, qr/\bif \(defined\(\$quantifier\)\)/,
        "chalk's Symbol::to_string keeps an if";
}

done_testing;
