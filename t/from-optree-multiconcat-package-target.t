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
subtest 'a package-target multiconcat stores through memory' => sub {
    my $out = translate_out(
        qq{our \$g = shift(\@ARGV) // "aaa";\n\$g = \$g . "x";\nprint qq{\$g\\n};\n});
    like $out, qr/"op"\s*:\s*"EntryWrite"/, 'the store is an EntryWrite';
    like $out, qr/"value"\s*:\s*"x"/, 'and the appended part is in the graph';
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

# THE .= FORM HAS A TARG AND STILL DROPS. Gating on a missing targ let this
# row through: the package `.=` carries targ=3, but that is a SCRATCH slot, not
# the destination.
#
#   pkg  $g = $g . "x"   targ=0 priv=0x00 flags=0x46  STACKED
#   pkg  $g .= "x"       targ=3 priv=0x40 flags=0x46  STACKED
#   lex  $l .= "x"       targ=1 priv=0x50 flags=0x06  TARGMY
#
# OPf_STACKED is the discriminating property; a lexical target is never
# stacked. Measured before the re-gate:
#
#     our $g = "a"; $g .= "x"; print "$g\n";
#       perl : ax
#       graph: string constants ['a', "\n"] -- no "x" anywhere
subtest 'a package-target .= also stores through memory' => sub {
    my $out = translate_out(qq{our \$g = "a";\n\$g .= "x";\nprint qq{\$g\\n};\n});
    like $out, qr/"op"\s*:\s*"EntryWrite"/, 'the store is an EntryWrite';
    like $out, qr/"value"\s*:\s*"x"/, 'and the appended part is in the graph';
};

subtest 'a lexical .= still lowers' => sub {
    my $out = translate_out(qq{my \$l = "a";\n\$l .= "x";\nprint qq{\$l\\n};\n});
    like $out, qr/"value"\s*:\s*"x"/, 'the appended part is in the graph';
};

done_testing;
