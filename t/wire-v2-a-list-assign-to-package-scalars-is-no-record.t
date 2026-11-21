# ABOUTME: A void list assignment whose scalars live in the stash is its EntryWrites: no Assign
# ABOUTME: is left beside them for the v2 writer to call a record of package variables (V7).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# WHY. `($a1, $b1) = ($b1 + 1, $a1 + 2)` stores each package scalar by an
# EntryWrite, position by position; the list Assign the handler made first
# stayed on the wire, on neither chain, read by nothing -- a `record` whose
# targets are not `my` variables (V7: probes lo12, m3; chalk's lib 4).
# STILL OPEN: probe pl13, the same assignment as its sub's last statement --
# then the Assign is the sub's value, and what node that value is (a list,
# or the right side's count) wants a design; chalk's wire-verify.t holds it.
my $dir = tempdir( CLEANUP => 1 );
my $n = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json,wire=2,not_package=SoN $f 2>/dev/null) );
}
sub v7 ($w) { [ map { "$_->{graph}#$_->{node}" } grep { $_->{rule} eq 'record' } SoN::Verify::verify($w)->{violations}->@* ] }

for my $case (
    [ q{our ($a1, $b1) = (0, 0); sub sw { ($a1, $b1) = ($b1 + 1, $a1 + 2); 1 } for (1..3) { $a1 = $a1 + 1; sw() } print "$a1 $b1\n";}, 'a swap of package scalars in a sub' ],
    [ q{our ($a1, $b1) = (1, 2); { local ($a1, $b1) = ($b1, $a1); print "$a1$b1" } print "$a1$b1\n";}, 'a local list assignment (lo12)' ],
    [ q{our $p = 1; ($p, my $q) = (3, 4); print "$p $q\n";}, 'a package scalar beside a `my` (m3)' ],
) {
    my ( $src, $name ) = @$case;
    is v7( wire($src) ), [], "$name: no record of a package variable";
}
done_testing;
