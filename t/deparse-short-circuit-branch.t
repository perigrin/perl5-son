# ABOUTME: An If with one Proj has an EMPTY other arm that falls through to the join.
# ABOUTME: `&&` in a condition compiles to nested Ifs, each keeping only the arm that acts.

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

# `&&` IN A CONDITION IS TWO NESTED IFS. Measured on
# `if (defined $a && $a > $b) { ... }`:
#
#      9 If    in=[0, 8]    ci=0     8 = And(Defined, NumGt)
#     10 Proj  in=[9]  index=0       the TRUE arm
#     13 Proj  in=[9]  index=1       the FALSE arm
#     14 If    in=[13, 8]  ci=13     a SECOND If on the same And
#     15 Proj  in=[14] index=1       only ONE Proj
#
# If(14) has no index-0 Proj because nothing happens on that arm -- control
# falls straight through to the join. The emitter required exactly two and
# refused, which is a refusal for a shape that is complete.
#
# EVERY PATH IS EXERCISED. A branch whose empty arm is emitted as the WRONG
# arm still produces output, so the check is all three outcomes: the condition
# true, false on the second test, and false on the first (short-circuited).
subtest 'an && condition round-trips' => sub {
    round_trips(<<'SRC', 'defined-and-compare, all three paths');
sub f {
    my ($a, $b) = @_;
    if (defined $a && $a > $b) { print "yes\n"; return 1 }
    print "no\n";
    return 0;
}
f(5, 1);
f(1, 5);
f(undef, 1);
SRC
};

# THE MISSING ARM CAN BE EITHER ONE. Measured across the three corpus files
# that refused:
#
#     comp/our.t        If(53) projs=[54 idx=1]
#     comp/multiline.t  If(15) projs=[16 idx=1], If(10) projs=[11 idx=1]
#     base/translate.t  If(17) projs=[23 idx=0]
#
# so a fix that assumed WHICH arm goes missing would pass two files and fail
# the third. base/translate.t's shape is `if (A || B) {...} elsif (C) {...}`
# inside a foreach, and the index-0 case is asserted against the real file
# rather than a synthetic reproduction -- several attempts at one produced two
# Projs, which is a reminder that the shape depends on context the source
# alone does not show.
subtest 'the index-0 case, from the corpus' => sub {
    my $t = 't/translate.t';
    my $path = -e "/home/perigrin/dev/perl5/t/base/translate.t"
        ? "/home/perigrin/dev/perl5/t/base/translate.t" : undef;
    skip_all 'perl source tree not available' unless $path;

    my $j = qx($^X -Ilib -MO=SoN,json,package=main $path 2>/dev/null);
    my $data = eval { JSON::PP->new->decode($j) };
    ok $data && $data->{methods}{'main::__PROGRAM__'}, 'it translates' or return;

    my @ns = ($data->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    my @one = grep {
        my $if = $_;
        ($if->{op} // '') eq 'If' && 1 == grep {
            ($_->{op} // '') eq 'Proj'
                && ((($_->{inputs} // [])->[0]) // -1) == $if->{id}
        } @ns;
    } @ns;
    ok scalar(@one), 'it has an If with one Proj' or return;

    my ($proj) = grep { ($_->{op} // '') eq 'Proj'
                     && ((($_->{inputs} // [])->[0]) // -1) == $one[0]{id} } @ns;
    is +($proj->{fields}{index}), 0, 'and the surviving arm is index 0';

    my $d = SoN::Deparse->new;
    ok defined $d->render($data), 'and it renders'
        or diag(($d->gap // '?') =~ s/\n.*//sr);
};

# A PLAIN TWO-ARM IF MUST NOT REGRESS -- it is the common case and the one the
# diamond logic was written for.
subtest 'a plain if/else still round-trips' => sub {
    round_trips(<<'SRC', 'both arms present');
my $x = @ARGV ? 1 : 0;
if ($x) { print "t\n" } else { print "f\n" }
print "done\n";
SRC
};

done_testing;
