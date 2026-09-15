# ABOUTME: chomp/chop must round-trip, including the store back to the target.
# ABOUTME: Their operand carries OPf_MOD genuinely, which is not a fresh read.

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

# The producer built `Call(schomp, [PadAccess])` consumed by NOBODY, so the
# mutation was invisible and the following read still named the original:
#
#     my $s = "ab\n"; chomp($s); print "[$s]"
#       perl : [ab]
#       graph: the Print reading the pre-chomp Constant
#
# And `schomp` is an op name, not a keyword, so the deparser emitted a call to
# a sub that does not exist before this was refused outright.
subtest 'a chomp stores back into its target' => sub {
    round_trips 'a pad scalar',
        qq{my \$s = "ab\\n";\nchomp(\$s);\nprint "[\$s]\\n";\n};
    round_trips 'twice',
        qq{my \$s = "ab\\n\\n";\nchomp(\$s);\nchomp(\$s);\nprint "[\$s]\\n";\n};
    round_trips 'a package scalar',
        qq{our \$g = "p\\n";\nchomp(\$g);\nprint "[\$g]\\n";\n};
    round_trips 'implicit \$_',
        qq{\$_ = "x\\n";\nchomp;\nprint "[\$_]\\n";\n};
    round_trips 'inside a sub',
        qq{sub t { my \$x = shift; chomp(\$x); return \$x }\nprint "[", t("q\\n"), "]\\n";\n};
};

# chop removes the LAST character whatever it is; chomp removes only a
# trailing $/. Two operations, and the node says which.
subtest 'chop is not chomp' => sub {
    round_trips 'a pad scalar',
        qq{my \$s = "abc";\nchop(\$s);\nprint "[\$s]\\n";\n};
    round_trips 'on a string with no newline',
        qq{my \$s = "abc";\nchomp(\$s);\nprint "[\$s]\\n";\n};
};

# chomp's operand carries OPf_MOD -- genuinely, since chomp writes -- and the
# padsv handler answers that by pushing an UNBOUND PadAccess. The Chomp then
# read a node nothing defines and `my $s = ...` vanished from the graph: the
# emitted program chomped an undeclared variable and printed "".
subtest 'the subject is the slot value, not a fresh read' => sub {
    round_trips 'an unfoldable initialiser',
        qq{my \$s = (shift(\@ARGV) // "z\\n");\nchomp(\$s);\nprint "[\$s]\\n";\n};
};

# THE LIST FORM IS MARK-DELIMITED. `chomp($p, $q)` compiles to the plain
# `chomp` op behind a pushmark, not `schomp`, and popping ONE node chomped
# only the last argument -- a silent miscompile that predates the Chomp node:
#
#     my ($p,$q) = ("a\n","b\n"); chomp($p,$q); print "$p$q"
#       perl : ab
#       emit : a\nb        -- $p never chomped
subtest 'a list chomp trims every argument' => sub {
    round_trips 'two',
        qq{my (\$p, \$q) = ("a\\n", "b\\n");\nchomp(\$p, \$q);\nprint "\$p\$q\\n";\n};
    round_trips 'three',
        qq{my (\$a, \$b, \$c) = ("1\\n", "2\\n", "3\\n");\nchomp(\$a, \$b, \$c);\nprint "\$a\$b\$c\\n";\n};
};

done_testing;
