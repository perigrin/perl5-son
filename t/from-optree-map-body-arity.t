# ABOUTME: A map/grep body contribution must have known arity, or the count is wrong.
# ABOUTME: sprintf yields exactly one value; sort, keys and split yield many.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use SoN::Deparse;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub translate ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $f 2>&1 >/dev/null);
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    return ($err, eval { JSON::PP->new->decode($out) });
}

# THE OUTPUT LENGTH IS THE QUESTION, and the answer turned out to be that
# NOBODY HAS TO COUNT. A map body contributing N values makes the result N
# times longer -- but the emission renders `(@acc, contribution)`, a plain
# list, so perl flattens it at runtime exactly as the source does. The producer
# never needs the arity for `map`.
#
# THIS FILE ASSERTED THE OPPOSITE and was right about the mechanism it could
# see: `translate()` below only TRANSLATES, so "it refuses rather than counting
# 1" was never checked against a running emission. Measured now:
#
#     my @a=(3,1); my @r = map { sort @a } (1);
#       perl                    2 [1 3]
#       my @phi4_next = (@phi4, sort(3, 1));
#       emitted program         2 [1 3]
#
# GREP IS DIFFERENT AND KEEPS THE REFUSAL. Its body is a PREDICATE: the
# contribution is the ELEMENT and the body's value only decides whether to take
# it, so a multi-value body there would append the wrong thing.
#
# `sprintf` YIELDS EXACTLY ONE, measured:
#
#     map { sprintf("%d", $_) } (1,2)   ->  2 elements
#     map { lc("AB") } (1)              ->  1
#
# and it was absent from the set, so comp/utf.t refused on it.
#
# THE OpMap TABLE CANNOT ANSWER THIS, which is worth recording because it
# looks as though it should: `sprintf => ['mark','Call',1,PURE]` has a 1 in
# the third slot, but so do `split`, `sort`, `keys` and `values`, which all
# yield MANY. That field is a stack push count -- one node -- not a result
# arity. So an explicit set is the honest mechanism here, not a lookup.
subtest 'sprintf in a map body' => sub {
    my $src = 'my @r = map { sprintf("%d", $_) } (1,2); print scalar(@r), " [@r]\n";';
    is run_perl($src), "2 [1 2]\n", 'perl yields one per element' or return;

    my ($err, $g) = translate($src);
    unlike $err, qr/GAP:|INTERNAL/, 'it translates' or diag $err;
    ok $g, 'and produces a graph';
};

# A MULTI-VALUE CONTRIBUTION ROUND-TRIPS. `sort` in a map body yields the whole
# sorted list, and the emitted program yields it too -- because it defers the
# flattening to perl rather than counting.
#
# ASSERTED BY RUNNING IT. The old form of this subtest checked only that a GAP
# appeared, which cannot distinguish "the refusal is necessary" from "the
# refusal is habitual".
subtest 'a multi-value contribution round-trips' => sub {
    my $src = 'my @a=(3,1); my @r = map { sort @a } (1); print scalar(@r), " [@r]\n";';
    my $want = run_perl($src);
    is $want, "2 [1 3]\n", 'perl yields the whole sorted list' or return;

    my ($err, $g) = translate($src);
    unlike $err, qr/GAP:|INTERNAL/, 'it translates' or diag $err;
    ok $g, 'and produces a graph' or return;

    my $out = eval { SoN::Deparse->new->render($g) };
    ok defined $out, 'and renders' or do { diag $@; return };
    is run_perl($out), $want, 'and the emitted program agrees with perl'
        or diag $out;
};

# GREP KEEPS THE CHECK IN THE PRODUCER, but this shape does not reach it: a
# grep body is evaluated in BOOLEAN context, so `sort @a` there is one truth
# value and never a multi-value contribution.
#
#     my @a=(3,1); grep { sort @a } (1,2)    perl: 0 []
#
# Asserted as a ROUND TRIP rather than as a refusal. A first draft of this
# subtest asserted `like $err, qr/GAP:/` on the assumption that grep would
# refuse where map now does not -- it does not refuse, and the assumption was
# never measured. What actually distinguishes them is that grep contributes the
# ELEMENT, which this checks by comparing the output.
subtest 'a multi-value grep body contributes the element' => sub {
    my $src = 'my @a=(3,1); my @r = grep { sort @a } (1,2); print scalar(@r), " [@r]\n";';
    my $want = run_perl($src);

    my ($err, $g) = translate($src);
    unlike $err, qr/GAP:|INTERNAL/, 'it translates' or diag $err;
    ok $g, 'and produces a graph' or return;

    my $out = eval { SoN::Deparse->new->render($g) };
    ok defined $out, 'and renders' or do { diag $@; return };
    is run_perl($out), $want, 'and agrees with perl' or diag $out;
};

# AND A KNOWN-ONE CONTRIBUTION THAT ALREADY WORKED must not regress.
subtest 'a scalar builtin still lowers' => sub {
    my $src = 'my @r = map { lc($_) } ("A","B"); print "@r\n";';
    is run_perl($src), "a b\n", 'perl lowercases each' or return;
    my ($err) = translate($src);
    unlike $err, qr/GAP:|INTERNAL/, 'it translates' or diag $err;
};

done_testing;
