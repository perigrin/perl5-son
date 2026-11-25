# ABOUTME: An lvalue op the producer has no store rule for is refused by name, never dropped (audit 2, K4);
# ABOUTME: a fused store (TARGMY, `.=` as multiconcat) handed to a sub is passed as its variable's place.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# THE DEFECT (second final audit, class K4): `($x = $x + 1) *= $x` printed 4
# for perl's 16, `($c ? $a : $b) x= 3` left $a alone, `for ($x += 5) { $_++
# }` lost the increment, `inc($x .= "b")` lost the callee's store. Each built
# the value and no store, with no GAP. perl compiles `$x = $x + 1` to an
# `add` storing into its targ (TARGMY), and `$x .= "b"` to a multiconcat
# doing the same: neither is the padsv or sassign the rules looked for.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ( $src, $err = '2>&1' ) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f $err);
}

for (
    [ 'my $x=3; ($x = $x + 1) *= $x; print "$x\n";',                         qr/GAP: an assignment used as the target of an op=/ ],
    [ 'my $x=3; my $y=1; ($x = $y + 1) *= 3; print "$x\n";',                 qr/GAP: an assignment used as the target of an op=/ ],
    [ 'my ($a1,$b1)=(1,2); my $c=1; ($c ? $a1 : $b1) x= 3; print "$a1 $b1\n";', qr/GAP: a \?: used as the target of an op=/ ],
    [ 'my $x=1; for ($x += 5) { $_++ } print "$x\n";',                       qr/GAP: an assignment as an item of a foreach, map or grep list/ ],
    [ 'my $x=1; for ($x = 5) { $_++ } print "$x\n";',                        qr/GAP: an assignment as an item of a foreach, map or grep list/ ],
    [ 'my $x=1; $_++ for ($x .= 5); print "$x\n";',                          qr/GAP: an assignment as an item of a foreach, map or grep list/ ],
) {
    my ( $src, $gap ) = @$_;
    like compile($src), $gap, "refused: $src";
}

# A FUSED STORE AS AN ARGUMENT passes its variable's place, as `inc($x += 1)` does.
for my $src (
    'sub inc { $_[0]++ } my $x="a"; inc($x .= "b"); print "$x\n";',
    'sub ap { $_[0].="!" } my $x="a"; ap($x .= "b"); print "$x\n";',
) {
    my $out = compile($src);
    unlike $out, qr/GAP/, "lowered: $src";
    my $w = eval { JSON::PP->new->decode( compile( $src, '2>/dev/null' ) ) };
    ok $w, "a wire: $src" or next;
    my @n = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %by = map { $_->{id} => $_ } @n;
    my ($call) = grep { $_->{op} eq 'Call' && ( $_->{fields}{dispatch_kind} // '' ) eq 'direct' } @n;
    my $arg = $by{ $call->{inputs}[0] };
    ok $arg && $arg->{op} eq 'PadAccess' && $arg->{fields}{place}, "the argument is \$x's place: $src";
}

done_testing;
