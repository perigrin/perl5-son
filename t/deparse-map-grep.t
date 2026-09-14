# ABOUTME: map/grep lower to a counted loop whose accumulator is a ListAppend.
# ABOUTME: The output length is not the input length, which is what ListAppend exists for.

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

# map LOWERS TO A COUNTED LOOP whose accumulator is a Phi over ListAppend.
# Measured on `my @s = map { $_ * 2 } (1,2,3)`:
#
#      5 ArrayLiteral in=[]           the EMPTY accumulator
#      7 Phi          in=[5, 27]      region=Loop
#     21 Phi          in=[20, 24]     the index
#     25 Subscript    in=[18, 21, 2]  the element, by index
#     27 ListAppend   in=[7, 26]      accumulator, contribution
#
# inputs[0] is the list so far and inputs[1..] are this iteration's
# contribution.
#
# THE OUTPUT LENGTH IS NOT THE INPUT LENGTH, which is the whole reason
# ListAppend exists rather than reusing the foreach lowering: the node's own
# ABOUTME says so. So a one-to-one map proves the least of any case here, and
# the zero and many cases are what separate a correct accumulator from a
# wrong one.
subtest 'map round-trips' => sub {
    round_trips(<<'SRC', 'one contribution per element');
my @s = map { $_ * 2 } (1, 2, 3);
print "@s\n";
SRC

    round_trips(<<'SRC', 'TWO contributions per element');
my @s = map { ($_, $_) } (1, 2);
print scalar(@s), " [@s]\n";
SRC

    round_trips(<<'SRC', 'NO contributions at all');
my @s = map { () } (1, 2);
print scalar(@s), " [@s]\n";
SRC
};

# grep CONTRIBUTES THE ELEMENT OR NOTHING, keyed on the predicate -- the same
# machinery with a different contribution.
subtest 'grep round-trips' => sub {
    round_trips(<<'SRC', 'a predicate that keeps some');
my @s = grep { $_ > 1 } (1, 2, 3);
print scalar(@s), " [@s]\n";
SRC

    round_trips(<<'SRC', 'a predicate that keeps none');
my @s = grep { $_ > 9 } (1, 2, 3);
print scalar(@s), " [@s]\n";
SRC
};

done_testing;
