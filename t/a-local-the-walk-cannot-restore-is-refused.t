# ABOUTME: A `local` whose restore the walk does not make -- under a condition, `delete local` -- is
# ABOUTME: refused by name; an operand read before `local` of its variable is the old scalar, read where it stands.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# THE DEFECTS (third final audit, N8). `our $g=1; sub p { print $g } { local
# $g = 5 if $c; p() } p()` printed 55 for perl's 51: the restore of a local
# that ran only on one path. `delete local $h{a}` deleted for good. And
# `print $g, local $g = 5` printed 55 for 15: the read of $g was made again
# after the local's store, as after any store -- but `local` gives the name
# a NEW scalar, and the operand is the old one.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1 >/dev/null);
}
my $cond = qr/GAP: a `local` under a condition/;
for my $case (
    [ 'our $g=1; sub p { print $g } my $c=1; { local $g = 5 if $c; p() } p(); print "\n";', $cond ],
    [ 'our $g=1; sub p { $g } sub t { $_[0] and local $g = 5; p() } print t(1), t(0), "\n";', $cond ],
    [ 'our $g=1; sub t { local $g = $_[0] ? 5 : 6 unless $_[1]; $g } print t(1, 0), "\n";', $cond ],
    [ 'our %h=(a=>1); sub t { my $v = delete local $h{a}; $v } print t(), $h{a}, "\n";', qr/GAP: `delete local` is not yet lowered/ ],
) {
    like compile( $case->[0] ), $case->[1], "refused: $case->[0]";
}
for my $src (
    'our $g=1; print $g, local $g = 5; print "\n";',
    'our $g=1; sub t { local $g = 5; $g } print t(), $g, "\n";',
    'our $g=1; sub t { local $g = $_[0] ? 5 : 6; $g } print t(1), $g, "\n";',
) {
    unlike compile($src), qr/GAP/, "not refused: $src";
}

# (the operand before the local is read where it stands: no read made again
# after the local's store)
{
    my $json = qx($^X -Ilib -MO=-q,SoN,json -e 'our \$g=1; print \$g, local \$g = 5;' 2>/dev/null);
    require JSON::PP;
    my @n = JSON::PP->new->decode($json)->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %by = map { ( $_->{id} => $_ ) } @n;
    my ($print) = grep { $_->{op} eq 'Print' } @n;
    my $first = $by{ $print->{inputs}[0] };
    my $first_read = $first->{op} eq 'Coerce' ? $by{ $first->{inputs}[0] } : $first;
    my ($local) = grep { $_->{op} eq 'EntryWrite' && ( $by{ $_->{inputs}[1] }{fields}{value} // '' ) eq '5' } @n;
    isnt $first_read->{mem_in} // -1, $local->{id}, 'the first $g is not read at the local\'s store';
}
done_testing;
