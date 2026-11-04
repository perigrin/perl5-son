# ABOUTME: A bitwise or shift op whose operand may be a string is pinned to its
# ABOUTME: statement: its numification of that operand happens where perl runs it.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src) {
    my $file = "$dir/p.pl";
    open my $fh, '>', $file or die; print {$fh} "$src\n"; close $fh;
    my $out = qx{$^X -Ilib -MO=-q,SoN,json $file 2>/dev/null};
    my $w = eval { JSON::PP->new->decode($out) } or return ();
    return ( $w->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
}

# Two statements: perl runs `$s & 5` (numifying $s) before `$s & "10"`.
# Floating, a backend lowers them where they are used -- in the other order.
{
    my @n = nodes_of(q{my $s = $ENV{X} // "12"; my $x = $s & 5; my $y = $s & "10"; print "$y $x\n";});
    my %by_id = map { $_->{id} => $_ } @n;
    my @bits = grep { $_->{op} eq 'BitAnd' } @n;
    is(scalar(@bits), 2, 'two ops');
    ok(( !grep { !defined $_->{control_in} } @bits ), 'each is pinned to the control chain');
    # The second's chain reaches the first: statement order.
    my ($first, $second) = @bits;
    my %seen;
    my $c = $second->{control_in};
    while (defined $c && !$seen{$c}++) { last if $c == $first->{id}; $c = $by_id{$c}{control_in} }
    is($c, $first->{id}, 'the second runs after the first');
}

# An op on numbers alone has nothing to numify: it stays a value.
{
    my @n = nodes_of(q{my $a = 6; my $b = 3; print $a & $b, "\n";});
    ok(( !grep { $_->{op} eq 'BitAnd' && defined $_->{control_in} } @n ), 'an op on Ints is not pinned');
}

done_testing;
