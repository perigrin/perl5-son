# ABOUTME: `for my $y ($x) { $x = 1; print $y }`: perl's $y is an alias of $x, the walk binds it to
# ABOUTME: $x's value; refused by name when the body may write the scalar, lowered when it only reads.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub warnings_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

# RE-AUDIT 2026-11-23, class E (probes/r e30, e31, q08, q11): the list was
# built as a literal of the value, so a write to the variable in the body was
# not seen through the iterator -- `my $x=5; for my $y ($x) { $x=1; print
# "$y\n" }` printed 5 for perl's 1.
my $GAP = qr/GAP: a foreach over a scalar variable its body may write is not yet lowered/;
my %refused = (
    'a store in the body'      => 'my $x=5; for my $y ($x) { $x=1; print "$y\n" }',
    'an increment'             => 'my $x=1; my $t=""; for my $y ($x) { $t.=$y; $x++; $t.=$y } print "$t\n";',
    'one of two variables'     => 'my ($p,$q)=(1,2); for my $y ($p) { $q=$y; $p=5; $q.=$y } print "$q\n";',
    'a package scalar, a call' => 'our $x=5; sub s1 { $x=1 } for my $y ($x) { s1(); print "$y\n" }',
    'through a reference'      => 'my $x=5; my $r=\$x; for my $y ($x) { $$r=1; print "$y\n" }',
    'the topic'                => 'my $x=5; for ($x) { $x=7; print "$_\n" }',
);
like warnings_of($refused{$_}), $GAP, "refused: $_" for sort keys %refused;

unlike warnings_of('my ($a1,$b1)=(1,2); my $t=0; for my $v ($a1,$b1) { $t+=$v } print "$t\n";'),
    qr/GAP: a foreach over a scalar/, 'a body that only reads the variables is not refused';

done_testing;
