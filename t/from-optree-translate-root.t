# ABOUTME: translate_root() walks a bare program's top-level optree (main_root/
# ABOUTME: main_start/main_cv), not a CV -- the entry half of the bare-file protocol.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempfile);
use FindBin;

my $PERL = $^X;
my $LIB  = "$FindBin::Bin/../lib";

# main_root/main_start/main_cv describe the OUTER compiled program; there is
# no way to isolate "just a required file" from them, so the target source
# under test and the driver that calls translate_root() must be ONE program,
# run as a real file (not eval STRING, which does not move main_root at all).
sub probe ($target_src) {
    my $combined = <<"COMBINED";
$target_src
use SoN::FromOptree;
my \$g = eval { SoN::FromOptree->translate_root() };
if (\$@) { print "ERROR: \$@"; exit 0; }
# NOTE: this driver is compiled as part of the probe program, so translate_root
# walks it too. It is deliberately kept OUT of the region under test by running
# after the target source -- the assertions below are about the target's ops,
# and the driver's own constructs (map, push, deref-foreach) are not the
# subject. When a refusal reaches this far it is reported through $@ above.
# The ops are collected with a WHILE loop over an index: this driver is
# compiled into the probe program and translate_root walks it too, so it has to
# stay inside what the walker lowers. `map { ... }` is now refused (the block
# would be dropped), and a foreach over a deref and `push` are refused as well
# -- each in turn broke this test.
my \@nodes = \$g->nodes->\@*;
my \$ops = "";
my \$i = 0;
while (\$i < scalar(\@nodes)) {
    \$ops = \$ops . \$nodes[\$i]->operation . ",";
    \$i = \$i + 1;
}
print "OPS: \$ops\\n";
print "HAS_START: ", (\$g->start ? "yes" : "no"), "\\n";
print "HAS_RETURN: ", (\@{\$g->returns} ? "yes" : "no"), "\\n";
COMBINED

    my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $combined;
    close $fh;

    return qx($PERL -I$LIB $path 2>&1);
}

subtest 'a bare arithmetic-and-print program translates via translate_root()' => sub {
    # @ARGV[0] keeps the addend a genuine runtime value (a literal `2 + 3`
    # folds to a Constant at parse time, before translate_root() ever runs).
    my $out = probe(qq{my \$x = \$ARGV[0] + 3;\nprint "\$x\\n";});
    diag($out) unless $out =~ /OPS:/;
    like($out, qr/HAS_START: yes/, 'graph has a Start node');
    like($out, qr/HAS_RETURN: yes/, 'graph has a Return (program exit) node');
    like($out, qr/\bAdd\b/, 'the arithmetic survives translation');
};

done_testing();
