# ABOUTME: A loop body that writes memory the scout did not foresee follows the header's memory
# ABOUTME: Phi, not the memory before the loop: a foreach writing its alias, a while pushing after its arms.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# WHY. The header memory Phi is decided before the body is walked (the
# scout, _body_stores_memory). A body that moved memory unforeseen got a
# late Phi for the exit only, and its own nodes kept the memory before the
# loop: the second pass's store followed the entry, not the first pass's
# store (V5, memory-order-disagrees: probes al16, lp28, corpus 205).
my $dir = tempdir( CLEANUP => 1 );
my $n = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json,wire=2,not_package=SoN $f 2>/dev/null) );
}
sub v5 ($w) { [ map { "$_->{graph}#$_->{node}" } grep { $_->{rule} eq 'memory-order-disagrees' } SoN::Verify::verify($w)->{violations}->@* ] }

for my $case (
    [ q{my @a = (1,2,3); for my $e (@a) { $e *= 2 } print "@a\n";}, 'a foreach that writes its alias (al16)' ],
    [ q{my @m = ([1,2],[3,4]); my $s = 0; for my $r (@m) { for my $c (@$r) { $s += $c; $c = 0 } } print "$s $m[1][1]\n";},
      'an inner foreach writing its alias (lp28)' ],
    [ q{sub f { my @c = @_; my @o; my $i = 0;
  while ($i <= $#c) { my $x = $c[$i];
    if ($x eq 'b') { if ($c[$i+1] eq 'w') { $i += 2; next } my $j = $i + 1; while ($j <= $#c) { $j++ } $i = $j; next }
    if ($x eq '.') { $i++; next }
    push @o, $x; $i++ }
  return "@o" }
print f(qw(a b w . c b x y)), "|", f(qw(a . b x)), "\n";},
      'a while that pushes after arms that end in next, one with a loop (corpus 205)' ],
) {
    my ( $src, $name ) = @$case;
    is v5( wire($src) ), [], "$name: every pinned node follows the memory control says";
}
done_testing;
