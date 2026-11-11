# ABOUTME: `last LABEL` (or next, redo) in a sub with no loop of its own leaves to its
# ABOUTME: caller's loop or block: refused by name, not dropped (Test::More's skip).
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);

for my $op (qw(last next redo)) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh "sub f { $op SKIP }\nSKIP: { f(); print \"no\\n\" }\nprint \"yes\\n\";\n";
    close $fh;
    my $err = qx($^X -Ilib -MO=-q,SoN,json $pl 2>&1 >/dev/null);
    like $err, qr/skipped main::f: GAP: a `$op` with no loop of its sub to leave/, "$op out of a sub: refused by name";
}
done_testing;
