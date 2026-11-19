# ABOUTME: A foreach over a range of strings ("a".."c") steps by perl's magic string
# ABOUTME: increment; it is refused by name, not lowered as a count from 0 to 0.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# FOUND UNDER W1 (audit probe tp7). The range foreach builds NumGt(high + 1,
# i) over Coerce(Str -> Num) of each bound: "a".."c" ran 0..0, one pass, with
# the iterator "a" -- `for my $c ("a".."c") { print $c }` printed `a` for
# perl's `abc`. A wrong answer the wire stated plainly.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub translate ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $err = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>&1 >/dev/null);
    return $err;
}

like translate('for my $c ("a".."c") { print $c } print "\n";'),
    qr/GAP: a foreach over a range of strings/, 'a string range is refused by name';
like translate('for my $c ("aa".."ad") { print $c } print "\n";'),
    qr/GAP: a foreach over a range of strings/, 'a longer one too';
unlike translate('for my $c ("1".."3") { print $c } print "\n";'),
    qr/GAP/, 'strings that are numbers are a numeric range';
unlike translate('for my $c (1..3) { print $c } print "\n";'),
    qr/GAP/, 'a numeric range is lowered';

done_testing;
