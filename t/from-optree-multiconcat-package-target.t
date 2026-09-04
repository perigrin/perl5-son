# ABOUTME: A multiconcat storing into a package scalar must not be lowered as a pure value.
# ABOUTME: perl fuses `$g = $g . "x"` into a STACKED multiconcat with no sassign to catch.

use v5.42.0;
use Test2::V0;

sub translate_err ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    unlink $file;
    return $err;
}

sub translate_out ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    return $out;
}

# `$g = $g . "x"` on a PACKAGE scalar is not an sassign. perl folds it into a
# multiconcat that writes its result to the destination SV on the stack:
#
#     package target:  multiconcat targ=0 private=0x00 flags=0x46 STACKED
#     lexical target:  multiconcat targ=1 private=0x10 flags=0x04
#
# The handler stores with $sim->define($op->targ, ...), and targ 0 for a
# package target is not "no target" -- it is "not a pad slot". Defining slot 0
# wrote a binding nothing reads, so the assignment vanished from the graph:
#
#     our $g = shift(@ARGV) // "aaa"; $g = $g . "x"; print "$g\n";
#       perl : aaax
#       before: no Concat for the append at all -- prints "aaa"
#
# Same root cause as the s/// package-target drop: targ 0 means the target is
# not a pad slot, and both of the things it covers need telling apart.
subtest 'a package-target multiconcat refuses rather than dropping the store' => sub {
    my $err = translate_err(
        qq{our \$g = shift(\@ARGV) // "aaa";\n\$g = \$g . "x";\nprint qq{\$g\\n};\n});
    like $err, qr/GAP: multiconcat storing into a package/, 'it refuses' or diag $err;
};

# The lexical form is the one that always worked and must keep working.
subtest 'a lexical-target multiconcat still lowers' => sub {
    my $out = translate_out(
        qq{my \$l = shift(\@ARGV) // "aaa";\n\$l = \$l . "x";\nprint qq{\$l\\n};\n});
    like $out, qr/"op"\s*:\s*"Concat"/, 'the append is in the graph';
};

# Interpolation into a package scalar READ is not a store and is unaffected.
subtest 'reading a package scalar in interpolation still lowers' => sub {
    my $out = translate_out(
        qq{our \$g = shift(\@ARGV) // "aaa";\nprint qq{[\$g]\\n};\n});
    like $out, qr/"op"\s*:\s*"Concat"/, 'the interpolation is in the graph';
};

done_testing;
