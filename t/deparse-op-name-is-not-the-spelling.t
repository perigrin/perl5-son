# ABOUTME: perl's op names are not always the keyword that produced them.
# ABOUTME: `printf` is the op `prtf`, and a filetest is an operator, not a call.

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

# The producer takes `name` from the OP, and `printf` is the op `prtf`.
# Emitting that verbatim gave "Undefined subroutine &main::prtf" --
# comp/bproto.t died on its first test, printing 2 lines of an expected 17.
subtest 'printf spells itself printf' => sub {
    round_trips 'a literal',  qq{printf("ok %d\\n", 7);\n};
    round_trips 'a variable', qq{my \$i = 3;\nprintf "n=%d\\n", \$i;\n};
    round_trips 'in a loop',  qq{for my \$i (1..3) { printf "%d\\n", \$i; }\n};
    round_trips 'two args',
        qq{my (\$a, \$b) = ("x", 5);\nprintf "%s=%d\\n", \$a, \$b;\n};
};

# A filetest is an OPERATOR -- `-e $f`, whose op is `ftis`. `ftis($f)` calls a
# sub that does not exist.
subtest 'a filetest is an operator' => sub {
    round_trips '-e', qq{print( (-e "/tmp") ? "yes\\n" : "no\\n" );\n};
    round_trips '-d', qq{print( (-d "/tmp") ? "dir\\n" : "no\\n" );\n};
};

# perl sets OPf_MOD on a plain pad READ passed to sprintf/printf, although
# neither writes it -- measured, `join`, `pack`, `push`, `print` and `substr`
# all leave the same read as plain `s`. Treating the flag as a write pushed a
# FRESH unbound PadAccess, so the emitted program read an undeclared variable:
#
#     my $i = 3; printf "n=%d\n", $i;
#       perl : n=3
#       emit : n=0
#
# A genuine in-place writer carries OPf_REF too (`chomp($i)` is `sRM`), so the
# flag alone never separated them; the CONSUMING op does.
subtest 'sprintf reads its operand, it does not write it' => sub {
    round_trips 'sprintf',
        qq{my \$i = 7;\nmy \$s = sprintf("v=%d", \$i);\nprint "\$s\\n";\n};
};

# `do EXPR` runs a file, and its op is `dofile`. It is a named unary
# operator, not a function.
subtest 'do FILE is an operator' => sub {
    round_trips 'a missing file',
        qq{my \$r = do "/tmp/claude-nonexistent-xyz.pl";\nprint defined \$r ? "def\\n" : "undef\\n";\n};
};

# An op with no Perl spelling must REFUSE rather than emit a call to a sub
# that does not exist. schomp is the case: the producer emits its Call with no
# store, so spelling it `chomp` would turn a loud "Undefined subroutine" into
# a silent wrong answer.
subtest 'an unspellable builtin refuses' => sub {
    my $d = SoN::Deparse->new;
    my $out = $d->render({ methods => { 'main::__PROGRAM__' => { nodes => [
        { id => 0, op => 'Start',  inputs => [] },
        { id => 1, op => 'PadAccess', inputs => [], fields => { sigil => '$', symbol => 's' } },
        { id => 2, op => 'Call', inputs => [1], control_in => 0,
          fields => { dispatch_kind => 'builtin', name => 'schomp' } },
        { id => 3, op => 'Return', inputs => [], control_in => 2 },
    ] } } });
    is $out, undef, 'it refuses rather than rendering';
    like $d->gap, qr/no Perl spelling/,
        'and the refusal names the reason';
};

done_testing;
