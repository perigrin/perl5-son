# ABOUTME: tr/// must round-trip, and a destructive one must store back.
# ABOUTME: A counting tr/// yields a number, which the graph cannot yet say.

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

# A destructive tr/// stores into its target, and without the rebind the node
# was consumed by NOBODY -- the following read still named the pre-tr value:
#
#     my $s = "hi"; $s =~ tr/a-z/A-Z/; print $s
#       perl : HI
#       emit : hi
subtest 'a destructive tr stores back' => sub {
    round_trips 'a range',
        qq{my \$s = "hi";\n\$s =~ tr/a-z/A-Z/;\nprint "\$s\\n";\n};
    round_trips 'delete',
        qq{my \$s = "axb";\n\$s =~ tr/x//d;\nprint "\$s\\n";\n};
    round_trips 'squash',
        qq{my \$s = "aaab";\n\$s =~ tr/a//s;\nprint "\$s\\n";\n};
};

# `r` yields a NEW string and leaves the source alone, so it must NOT rebind.
subtest 'the r form does not mutate its subject' => sub {
    round_trips 'a range',
        qq{my \$s = "hi";\nmy \$t = (\$s =~ tr/a-z/A-Z/r);\nprint "\$s \$t\\n";\n};
};

# A non-void tr/// yields a COUNT. perl compiles `my $n = ($s =~ tr/a//)` in
# SCALAR context where the destructive form is VOID, and pushing the
# transliterated string there was a wrong value AND a wrong type -- measured,
# `2` came out as `aab`.
#
# NOT RegexSubstCount: the two counts are different TYPES. Measured on 5.42.0,
# `"xyz" =~ tr/a//` is a real 0 while `"xyz" =~ s/a/b/` is the EMPTY STRING,
# so one node could not carry a stamp true of both.
subtest 'a counting tr yields a number' => sub {
    round_trips 'some matches',
        qq{my \$s = "aab";\nmy \$n = (\$s =~ tr/a//);\nprint "\$n\\n";\n};
    round_trips 'no matches',
        qq{my \$s = "xyz";\nmy \$n = (\$s =~ tr/a//);\nprint "[\$n]\\n";\n};
};

# NO TARG MEANS $_, which is nameable: it is the package scalar main::_, an
# ordinary SSA binding the s/// handler already keys the same way. Refusing it
# killed the whole program -- the GAP propagates out of translate() and
# base/lex.t lost its __PROGRAM__ entirely.
subtest 'a tr on $_ binds the real variable' => sub {
    round_trips 'tr',
        qq{\$_ = "a";\ntr[a][b];\nprint "\$_\\n";\n};
    round_trips 'y',
        qq{\$_ = "a";\ny[a][b];\nprint "\$_\\n";\n};
};

done_testing;
