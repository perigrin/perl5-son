# ABOUTME: `\$x` taken on each pass of a loop that gives $x a fresh variable (a my in
# ABOUTME: the body) says so on its Ref (fresh_each_pass); a variable made once does not.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub son_json ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1);
    unlink $f; return $out;
}

# Each pass's \$x names that pass's $x in perl. A consumer with one location
# per lexical names the last pass's with every one (chalk, pvm 219 printed
# 2,2 for 1,2): the Ref says so.
for my $src (
    q{my @l; for my $i (0, 1) { my $x = $i + 1; push @l, \$x } print ${ $l[0] }, "\n";},
    q{my @l; for my $i (0, 1) { my $x = $i + 1; $l[$i] = \$x } print ${ $l[0] }, "\n";},
    q{my @l = map { my $x = $_; \$x } 1, 2; print ${ $l[0] }, "\n";},
    q{my @l; my $i = 0; while ($i < 2) { my $x; $x = $i; push @l, \$x; $i++ } print ${ $l[0] }, "\n";},
) {
    like son_json($src), qr/"fresh_each_pass"/, "marked: $src";
}

# A variable made once, outside the loop, is the same one on every pass; a
# foreach variable aliases the element it walks.
for my $src (
    q{my @l; my $x = 1; for my $i (0, 1) { push @l, \$x } print ${ $l[0] }, "\n";},
    q{my $x = 5; my $r = \$x; $$r = 6; print "$x\n";},
    q{my @a = (1, 2); my @r; for my $x (@a) { push @r, \$x } ${ $r[1] } = 9; print "@a\n";},
) {
    my $j = son_json($src);
    unlike $j, qr/fresh_each_pass/, "not marked: $src";
}

done_testing;
