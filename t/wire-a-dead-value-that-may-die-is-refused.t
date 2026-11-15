# ABOUTME: a value that may die (a division by what may be zero, a reference before an
# ABOUTME: array's start) and is never used is refused by name, not dropped from the graph.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir(CLEANUP => 1);

sub son_json ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1);
    unlink $f; return $out;
}

# perl evaluates `1 / $z` even with nothing reading it, and dies. The walk
# built the Divide and nothing reached it: the graph was the print alone,
# and the program printed "x" where perl dies (an older wrong answer).
for my $src (
    q{my $z = 0; my $q = 1 / $z; print "x\n";},
    q{my $z = $ENV{NOPE} // 0; my $q = 7 % $z; print "x\n";},
) {
    like son_json($src), qr/GAP: .*may die.*never used|GAP: .*never used.*may die/, "refused: $src";
}

# Used, or not able to die, it is graphed as before.
for my $src (
    q{my $z = 2; my $q = 1 / $z; print "$q\n";},
    q{my $q = 1 / 4; print "x\n";},
    q{my $z = $ENV{NOPE} // 2; print 1 / $z, "\n";},
    q{my @a = (1, 2); my $p = \$a[-1]; print $$p, "\n";},
) {
    unlike son_json($src), qr/GAP: /, "not refused: $src";
}

# A REFERENCE TO AN ELEMENT IS NO DEAD VALUE: it stands where it is taken, on
# the control chain (the element at its index then), so a consumer makes it
# there -- and dies there, before the start, as perl does.
{
    my $src = q{my @a = (1, 2); my $p = \$a[-5]; print "x\n";};
    my $out = son_json($src);
    unlike $out, qr/GAP: /, "not refused: $src";
    my $w = eval { JSON::PP->new->decode($out =~ s/\A[^{]*//r) };
    my @r = grep { $_->{op} eq 'Ref' } ( $w->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    ok @r == 1 && defined $r[0]{control_in}, 'the reference is on the control chain';
}

done_testing;
