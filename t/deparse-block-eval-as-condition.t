# ABOUTME: A block eval refuses -- the wire records its join but not its entry.
# ABOUTME: A string eval renders, because its Region's input IS the eval.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
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

# A BLOCK EVAL'S VALUE IS 1-OR-UNDEF, and `if (eval { ... })` reads it.
# Measured on `if (eval { $g = 1; 1 }) {...}`:
#
#     16 Region in=[10]      a SINGLE-input Region
#     17 Phi    in=[6, 1]    the block's value, or undef if it died
#     18 If     in=[16, 17]  the Phi IS the condition
#
# The Phi's region is neither a Loop (so it is not loop-carried) nor a
# two-armed branch join (so _join_phis does not own it), which is why the Phi
# rule refused it.
#
# base/rs.t's test_bad_setting is this shape eight times over:
# `if (eval { $/ = \0; 1 }) { ... } else { ... }`.
#
# THE BODY RUNS FROM THE ENTRY TO THE JOIN. The Region names the control node
# the protected body began after (`eval_entry`), which is what makes the block
# delimitable at all -- before it was recorded, the statements an eval protects
# were indistinguishable from those before it.
#
# CLAIMED AT THE ENTRY, NOT AT THE JOIN. A block eval's body is ordinary chain
# between the two, so recognising the construct when the walk ARRIVES at the
# Region emits those statements twice -- measured, they appeared both before
# the `eval {` and inside it, and a `die` among them escaped.
#
# BOTH OUTCOMES ARE CHECKED, and the side effect with them: a rule that always
# took the success branch still prints something, and only the dying case
# separates it.
subtest 'a block eval as a condition' => sub {
    round_trips(<<'SRC', 'the block completes');
our $g = 0;
if (eval { $g = 1; 1 }) { print "ok g=$g\n" } else { print "died g=$g\n" }
SRC

    round_trips(<<'SRC', 'the block dies');
our $g = 0;
if (eval { $g = 1; die "x\n"; 1 }) { print "ok g=$g\n" } else { print "died g=$g\n" }
SRC

    # STATEMENTS BEFORE THE EVAL MUST STAY OUTSIDE IT -- that is the case the
    # entry exists to get right, and the one that escaped a die when the body
    # was guessed.
    round_trips(<<'SRC', 'statements before the eval stay outside');
our $g = 0;
our $h = 0;
$h = 5;
if (eval { $g = 1; 1 }) { print "ok g=$g h=$h\n" } else { print "died\n" }
SRC
};

# A STRING EVAL STILL RENDERS -- its Region's input IS the eval, so the body
# needs no delimiting. That is what makes this about the BLOCK form.
subtest 'a string eval still round-trips' => sub {
    round_trips(<<'SRC', 'a value-producing string eval');
my $v = eval "1+1";
print "[$v]\n";
SRC
};

# A PLAIN CONDITION MUST NOT REGRESS -- an ordinary If whose condition is a
# comparison is the common case.
subtest 'an ordinary condition still round-trips' => sub {
    round_trips(<<'SRC', 'a numeric test');
my $x = @ARGV ? 9 : 2;
if ($x > 1) { print "big\n" } else { print "small\n" }
SRC
};

done_testing;
