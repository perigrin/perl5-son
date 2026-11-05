# ABOUTME: `use integer` arithmetic (i_add, i_multiply, ...) and bitwise ops under it
# ABOUTME: are refused by name -- mapped onto the plain ops, 7 * 1.5 was 10.5, not 7.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub producer_err ($src) {
    my $file = "$dir/p.pl";
    open my $fh, '>', $file or die; print {$fh} "$src\n"; close $fh;
    return scalar qx{$^X -Ilib -MO=-q,SoN,json $file 2>&1 >/dev/null};
}

for my $case (
    [ q{use integer; my $x = 7; print $x * 1.5, "\n";}, 'i_multiply' ],
    [ q{use integer; my $x = $ENV{X} // 7; print $x / 2, "\n";}, 'i_divide' ],
    [ q{use integer; my $x = $ENV{X} // 7; print $x + 0.5, "\n";}, 'i_add' ],
    [ q{use integer; my $a = $ENV{X} // 5; print $a & -2, "\n";}, 'a bitwise op, signed under it' ],
) {
    my ($src, $name) = @$case;
    like(producer_err($src), qr/GAP: .*use integer/, "$name: refused by name");
}

# Outside its scope, the plain ops are unchanged.
unlike(producer_err(q{my $x = 7; print $x * 1.5, "\n";}), qr/GAP/, 'no use integer: no refusal');

done_testing;
