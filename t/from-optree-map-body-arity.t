# ABOUTME: A map/grep body contribution must have known arity, or the count is wrong.
# ABOUTME: sprintf yields exactly one value; sort, keys and split yield many.

use v5.42.0;
use Test2::V0;
use JSON::PP;
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

# THE OUTPUT LENGTH IS THE QUESTION. A map body contributing N values makes
# the result N times longer, so a contribution whose arity is unknown cannot
# be appended -- `ListAppend` would count 1 where perl counts N. That refusal
# is right, and the set of things known to yield ONE is what it keys on.
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

# A MULTI-VALUE CONTRIBUTION MUST STILL REFUSE. `sort` in a map body yields
# the whole sorted list, so appending it as one value would count 1 where
# perl counts N -- which is the defect the refusal exists to prevent.
subtest 'a multi-value contribution still refuses' => sub {
    my $src = 'my @a=(3,1); my @r = map { sort @a } (1); print scalar(@r), "\n";';
    is run_perl($src), "2\n", 'perl yields the whole sorted list' or return;

    my ($err) = translate($src);
    like $err, qr/GAP:/, 'it refuses rather than counting 1';
};

# AND A KNOWN-ONE CONTRIBUTION THAT ALREADY WORKED must not regress.
subtest 'a scalar builtin still lowers' => sub {
    my $src = 'my @r = map { lc($_) } ("A","B"); print "@r\n";';
    is run_perl($src), "a b\n", 'perl lowercases each' or return;
    my ($err) = translate($src);
    unlike $err, qr/GAP:|INTERNAL/, 'it translates' or diag $err;
};

done_testing;
