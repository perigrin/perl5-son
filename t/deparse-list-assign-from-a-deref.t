# ABOUTME: A PostfixDeref is a target in `$$r = 7` and a SOURCE in `my (@a) = @$r`.
# ABOUTME: Position separates them; the node kind cannot.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

sub run_src ($src) {
    my $file = __FILE__ . ".run.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $file 2>&1);
    unlink $file;
    return $out;
}

sub emit ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return SoN::Deparse->new->render($data);
}

sub round_trips ($name, $src) {
    my $emitted = emit($src);
    ok defined $emitted, "$name: it renders" or return;
    is run_src($emitted), run_src($src), "$name: it agrees with perl"
        or diag "emitted:\n$emitted";
}

# The Assign branch walks its leading inputs while they are targets, and
# PostfixDeref was unconditionally one -- for `$$r = 7`, which is right. But
# `my ($a,$b) = @$r` puts a PostfixDeref in the SOURCE position, so walking it
# as a third target left NO values and refused. Measured on comp/require.t:
#
#     Assign in=[PadAccess x5, PostfixDeref]      -- `my (...) = @$ref`
#
# A trailing PostfixDeref after pad targets cannot be a target: a list
# assign's targets are all lvalues, and perl writes `($$r, $$s) = ...` with
# the derefs FIRST, never one deref after five pad slots.
subtest 'a trailing deref is the source, not a target' => sub {
    round_trips 'two targets',
        qq{my \$r = [1,2];\nmy (\$a, \$b) = \@\$r;\nprint "\$a\$b\\n";\n};
    round_trips 'one target',
        qq{my \$r = [9];\nmy (\$a) = \@\$r;\nprint "\$a\\n";\n};
};

# The target forms must not regress: a deref FIRST is still an lvalue.
subtest 'a leading deref is still a target' => sub {
    round_trips 'one deref store',
        qq{my \$x = 1;\nmy \$r = \\\$x;\n\$\$r = 7;\nprint "\$x\\n";\n};
    round_trips 'two deref stores',
        qq{my (\$x, \$y) = (1, 2);\nmy (\$p, \$q) = (\\\$x, \\\$y);\n(\$\$p, \$\$q) = (8, 9);\nprint "\$x\$y\\n";\n};
};

done_testing;
