# ABOUTME: A map over split must see every field, not a one-element list.
# ABOUTME: The loop bound collapsed to 1, and on real input it did not terminate.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

sub run_src ($src) {
    my $file = __FILE__ . ".run.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $file 2>&1);
    unlink $file;
    return $out;
}

sub emit ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return SoN::Deparse->new->render($data);
}

# FOUND BY A PROCESS THAT HAD BEEN SPINNING FOR 28 HOURS. The deparse of
# comp/retainedlines.t emitted a loop whose bound re-evaluates split every
# iteration and collapses it to a one-element count:
#
#     while ((scalar(() = (scalar(() = split(qr{\n}, $prog, 0)))) > $phi59))
#
# The doubled `scalar(() = ...)` counts the LIST HOLDING the split result,
# not its fields, so the bound is 1 however many lines $prog has. Reduced:
#
#     my @lines = map { "$_\n" } split /\n/, $prog;   # $prog = "a\nb\nc"
#       perl : 3
#       emit : 1
#
# The wrong ANSWER was the defect; the non-termination on real input was the
# same bug meeting a bound that never catches up.
#
# FIXED by rendering the count as `do { my @cN = LIST; scalar(@cN) }`. The
# named temporary is what makes split size itself correctly -- assigning to an
# EMPTY list told it zero fields were wanted, and it obliged.
subtest 'a map over split sees every field' => sub {
    my $src = <<'PERL';
sub f {
    my ($prog) = @_;
    my @lines = map { "$_\n" } split /\n/, $prog;
    return scalar @lines;
}
print f("a\nb\nc"), "\n";
PERL

    my $emitted = emit($src);
    ok defined $emitted, 'it renders' or return;

    is run_src($emitted), run_src($src), 'it agrees with perl'
        or diag "emitted:\n$emitted";
};

# THE ROOT CAUSE IS NARROWER AND WORSE than the map framing suggests: a
# split COUNT renders as `scalar(() = split(...))`, and that is a list
# assignment in scalar context -- which yields the count of the LEFT side,
# an empty list, not the fields. Measured on the simplest possible case:
#
#     my @l = split /,/, "a,b,c"; print scalar(@l)
#       perl : 3
#       emit : 1, from `scalar(() = split(qr{,}, "a,b,c", 0))`
#
# So every split count is wrong, and the map bound above is one consumer of
# it. The 28-hour hang was that bound never catching up.
subtest 'a split count is the fields, not the empty LHS' => sub {
    my $src = qq{my \@l = split /,/, "a,b,c";\nprint scalar(\@l), "\\n";\n};
    my $emitted = emit($src);
    ok defined $emitted, 'it renders' or return;

    is run_src($emitted), run_src($src), 'it agrees with perl'
        or diag "emitted:\n$emitted";
};

done_testing;
