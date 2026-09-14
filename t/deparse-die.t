# ABOUTME: An Unwind is a `die`, in a branch arm or as a sub body's terminator.
# ABOUTME: Verified by RUNNING the emitted program -- a dropped die changes the exit.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); my $rc = $?; unlink $f;
    return ($out, $rc);
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# A die WITHOUT A TRAILING NEWLINE APPENDS " at FILE line N." -- perl's rule,
# and the emitted file has a different name and different line numbers, so the
# two can never agree on that suffix. It is not a rendering difference: the
# message, the fact of dying, and the exit status all match.
#
# Normalised rather than avoided, because a bare `die` is 3 of the 12 measured
# nodes and testing only the newline-terminated form would leave that path
# unchecked.
sub _norm ($s) { $s =~ s{ at \S+ line \d+\.}{ at FILE line N.}gr }

sub round_trips ($src, $name) {
    my ($want, $want_rc) = run_perl($src);
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
    my ($got, $got_rc) = run_perl($out);
    is _norm($got), _norm($want), $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";

    # A DROPPED die STILL PRINTS THE SAME THING up to the point it would have
    # fired, so the exit status is what separates "died" from "fell through".
    is !!$got_rc, !!$want_rc, "$name: and the same exit disposition";
}

# AN Unwind IS A `die`. Measured across the three corpus files that refused,
# twelve nodes, uniform: no fields, control_in is the chain predecessor, and
# inputs is either one value node or nothing. The producer builds it at two
# sites and both comments say `die`.
#
# TWO SHAPES, and the message hid the difference:
#
#   arm terminator   control_in is an If's Proj; the Unwind is consumed as a
#                    Region input (the join). 11 of 12.
#   body terminator  control_in is Start directly, no Region names it, and a
#                    Return follows it. 1 of 12 (require.t's `sub v5 { die }`).
#
# One spelling covers both, because it is the node's own semantics: `die EXPR`
# with an input, `die` without.
subtest 'die in a branch arm' => sub {
    round_trips(<<'SRC', 'the arm that dies is not taken');
my $x = 1;
if ($x) { print "ok\n" } else { die "bad\n" }
print "end\n";
SRC

    round_trips(<<'SRC', 'the arm that dies IS taken');
my $x = 0;
if ($x) { print "ok\n" } else { die "bad\n" }
print "end\n";
SRC
};

# ZERO INPUTS. 3 of the 12 measured nodes are a bare `die`, and an emitter
# that indexed inputs[0] unconditionally would render `die undef`, which is a
# different message.
subtest 'a bare die' => sub {
    round_trips(<<'SRC', 'die with no argument');
my $x = 0;
if ($x) { print "ok\n" } else { die }
print "end\n";
SRC
};

# THE BODY-TERMINATOR SHAPE, which is require.t's `sub v5 { die }`: control_in
# is Start, and a Return follows the Unwind in the chain. Dead code after a
# die is unreachable, so it stays observationally equivalent -- but the walk
# must not refuse it.
subtest 'die as a sub body' => sub {
    round_trips(<<'SRC', 'a sub whose body is a die, never called');
sub v5 { die }
print "end\n";
SRC

    round_trips(<<'SRC', 'a sub whose body is a die, called');
sub boom { die "boom\n" }
print "before\n";
boom();
print "unreached\n";
SRC
};

done_testing;
