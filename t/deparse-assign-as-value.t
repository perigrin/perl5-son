# ABOUTME: An assignment used as a value renders as the assignment, parenthesised.
# ABOUTME: A list assign in scalar context is the RHS element COUNT, not the last value.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
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

# AN ASSIGNMENT IS A VALUE. Measured on base/lex.t's
# `my ($p,$f,$l) = caller;` reached as an operand:
#
#      14 Assign  in=[10,11,12,13]  stamp=List
#      15 Coerce  in=[14]           Unknown -> Str
#
# so a list Assign's VALUE is read, not only its effect.
#
# A LIST ASSIGN IN SCALAR CONTEXT IS THE RHS ELEMENT COUNT -- not the last
# value, and not the number of targets. `my $n = (my ($a,$b) = (7,8,9))` is 3.
# That is the idiom `scalar(() = LIST)` relies on, and getting it wrong
# produces a number that still looks plausible.
# THE TARGETS ARE NOT READ BACK HERE, deliberately. A list assign to
# PREVIOUSLY DECLARED variables does not rebind them in the producer -- a
# separate defect, pinned in t/from-optree-list-assign-rebinds.t -- so a case
# that also read $a afterwards would fail for two reasons and prove neither.
# What this checks is the VALUE the assignment yields.
subtest 'a list assign used as a value' => sub {
    round_trips(<<'SRC', 'the count, not the last element');
my ($a, $b);
my $n = (($a, $b) = (7, 8, 9));
print "n=$n\n";
SRC

    round_trips(<<'SRC', 'fewer values than targets counts the VALUES');
my ($a, $b, $c);
my $n = (($a, $b, $c) = (1, 2));
print "n=$n\n";
SRC
};

# A SCALAR ASSIGN YIELDS THE VALUE ASSIGNED, which is the other reading and
# must not be confused with the count.
subtest 'a scalar assign used as a value' => sub {
    round_trips(<<'SRC', 'the value, in a condition');
my $x;
print(($x = 5) ? "t\n" : "f\n");
print "x=$x\n";
SRC

    round_trips(<<'SRC', 'and a false value is false');
my $x;
print(($x = 0) ? "t\n" : "f\n");
print "x=$x\n";
SRC
};

done_testing;
