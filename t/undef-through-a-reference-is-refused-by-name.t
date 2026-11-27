# ABOUTME: `undef $$r` is refused by name; it died as an internal error on the dereference's missing
# ABOUTME: name, which B::SoN masks as a skip with no name (audit 4, xd42/xq01).
use v5.42.0;
use Test2::V0;

for my $src ( 'my $x = 5; my $r = \$x; undef $$r; print defined $x ? "d" : "u", "\n";',
              'our $x = 5; my $r = \$x; undef ${$r}; print defined $x ? "d" : "u", "\n";' ) {
    my $err = qx($^X -Ilib -MO=-q,SoN,json -e '$src' 2>&1 >/dev/null);
    like $err, qr/GAP: undef\(EXPR\) of a scalar through a reference/, "refused by name: $src";
    unlike $err, qr/INTERNAL ERROR/, "no internal error: $src";
}
done_testing;
