# ABOUTME: A `local` of a named package scalar binds the name to a new scalar (design B, section 4), so a
# ABOUTME: place taken before keeps the old one (audit 2, K2); an element localized under an alias is refused.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# THE DEFECT (second final audit, class K2): `our $x=1; sub f { local $x=5;
# $_[0]=7; $x } print f($x), $x` printed 71 for perl's 57. `local` gives the
# NAME a new scalar; $_[0] still holds the old one. The wire models local as
# save, store, restore on one location, and a place is a pointer to that
# location, so the store lands in the new value. Design B (section 4): a
# place is the scalar; `local` binds the name to a new scalar (EntryWrite
# `local`), saved as a reference to the old one and bound back on every way
# out (EntryWrite `binds` of that reference). An element's local is not yet a
# new scalar -- chalk's element alias is the aggregate and the key -- so a
# call handing an element to a sub that localizes it stays refused.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1);
}
my $gap = qr/GAP: an element handed to a sub as its \$_\[N\] where that sub localizes it/;
use JSON::PP ();
sub wire_of ($src) {
    my $f = "$dir/w" . ++$n . '.pl';
    open my $o, '>', $f or die $!; print $o $src; close $o;
    my $j = qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null);
    return eval { JSON::PP->new->decode($j) };
}

for my $src (
    'our $x=1; sub f { local $x=5; $_[0]=7; $x } print f($x),$x,"\n";',
    'our $x=1; sub f { local $x=5; $_[0]++; $x } print f($x), $x, "\n";',
    'our $x=1; sub f { local $x=5; g2($_[0]) } sub g2 { $_[0]=7; $x } print f($x), $x, "\n";',
    '$main::x=1; my %d=(f=>sub { local $main::x=5; $_[0]=7; $main::x }); print $d{f}->($main::x),$main::x,"\n";',
) {
    my $w = wire_of($src);
    ok $w, "lowered: $src" or next;
    my @n = map { $_->{nodes}->@* } values $w->{methods}->%*;
    ok( ( grep { $_->{op} eq 'EntryWrite' && ( $_->{fields} // {} )->{local} } @n ), "  a local is a new scalar (EntryWrite local)" );
    ok( ( grep { my $v = $_; $v->{op} eq 'EntryWrite' && ( $v->{fields} // {} )->{binds} } @n ), "  its restore binds the saved scalar back" );
}
like compile('our %h=(k=>1); sub f { local $h{k}=5; $_[0] } print f($h{k}), "\n";'), $gap, 'refused: an element localized under an alias';

# (no place, or no local of what it names: lowered as before)
for my $src (
    'our $x=1; sub f { local $x=5; $_[0] } print f($x),$x,"\n";',
    'our $x=1; sub g { $_[0]=7 } sub f { local $x=5; g($x); $x } print f(),$x,"\n";',
    'our ($x,$y)=(1,2); sub f { local $y=5; $_[0]=7; $y } print f($x),$x,"\n";',
    # (a code value, where nothing the program has localizes what it is handed)
    'sub apply { my ($f,@l)=@_; map { $f->($_) } @l } my @r=apply(sub { $_[0]*2 }, 1,2); print "@r\n";',
    'sub k { $_[1]->(); $_[0] } sub w { my $v=1; my $s=sub { $v=9 }; k($v,$s) } print w(),"\n";',
) {
    unlike compile($src), qr/GAP/, "not refused: $src";
}

done_testing;
