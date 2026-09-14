# ABOUTME: A scalar `my $s = <FH>` binds the readline's value to the pad slot.
# ABOUTME: perl nulls the sassign and stacks the destination on readline itself.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub call_named ($g, $name) {
    my ($n) = grep {
        $_->operation eq 'Call' && ($_->name // '') eq $name
    } $g->nodes->@*;
    return $n;
}

sub ops_of ($g) { return join ' ', map { $_->operation } $g->nodes->@* }

# `my $s = <$fh>` compiles with NO sassign on the exec chain. Measured:
#
#     padsv[$s]  sRM*/LVINTRO      the destination, pushed first
#     gvsv[*fh]  s
#     readline[t5] sKS/1           OPf_STACKED -- the destination is stacked
#     null       /0x45             the sassign, NULLED and off the chain
#
# readline pops only its handle, so the destination PadAccess was left on the
# stack and the read's value reached nothing. The contrast that places the
# defect: `my $e = eof($fh)` gets a real padsv_store and binds correctly, and
# `my @l = <$fh>` gets a real aassign and binds correctly. Only the
# scalar-context readline carries the store on the op's own OPf_STACKED.
subtest 'scalar readline binds its value to the pad slot' => sub {
    my $g = graph_of('sub { open(my $fh,"<","x"); my $s = <$fh>; $s }');
    my $rl = call_named($g, 'readline');
    ok(defined $rl, 'the readline Call is present') or return;

    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok(defined $ret, 'the sub has a Return') or return;

    is($ret->inputs->[0], $rl,
        'the returned value IS the readline result, not an unbound PadAccess')
        or diag('ops = [' . ops_of($g) . ']');
};

# The same drop, with no `my`: perl stacks the destination on readline for a
# plain rebind too (padsv sRM* with no LVINTRO).
subtest 'scalar readline into an existing slot rebinds it' => sub {
    my $g = graph_of('sub { open(my $fh,"<","x"); my $s; $s = <$fh>; $s }');
    my $rl = call_named($g, 'readline');
    ok(defined $rl, 'the readline Call is present') or return;

    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    is($ret->inputs->[0], $rl,
        'the returned value IS the readline result')
        or diag('ops = [' . ops_of($g) . ']');
};

# The `while (my $line = <$fh>)` idiom is the same shape inside a loop: the
# readline feeds Defined for the condition AND must bind $line for the body.
subtest 'while-loop readline binds the loop variable' => sub {
    my $g = graph_of(
        'sub { open(my $fh,"<","x"); my $n = 0;'
      . ' while (my $line = <$fh>) { $n = length($line) } $n }');
    my $rl = call_named($g, 'readline');
    ok(defined $rl, 'the readline Call is present') or return;

    my ($len) = grep { $_->operation eq 'Length' } $g->nodes->@*;
    ok(defined $len, 'the Length node is present') or return;

    is($len->inputs->[0], $rl,
        'length() reads the readline result, not an unbound PadAccess')
        or diag('ops = [' . ops_of($g) . ']');
};

# TEETH: the sibling handle builtins keep their padsv_store path. A fix keyed
# on the op NAME rather than on OPf_STACKED would either miss these or
# double-store them.
subtest 'eof/tell still bind through padsv_store' => sub {
    for my $bi (qw( eof tell )) {
        my $g = graph_of("sub { open(my \$fh,\"<\",\"x\"); my \$v = $bi(\$fh); \$v }");
        my $call = call_named($g, $bi);
        ok(defined $call, "the $bi Call is present") or next;
        my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
        is($ret->inputs->[0], $call, "$bi's value is bound to the pad slot")
            or diag("ops = [" . ops_of($g) . "]");
    }
};

# TEETH: a readline with NO destination (void, or feeding an expression) must
# not grow a phantom store. `<$fh>` in list context still goes to aassign.
subtest 'list readline is unchanged' => sub {
    my $g = graph_of('sub { open(my $fh,"<","x"); my @l = <$fh>; $l[0] }');
    my $rl = call_named($g, 'readline');
    ok(defined $rl, 'the readline Call is present') or return;
    my ($arr) = grep { $_->operation eq 'ArrayLiteral' } $g->nodes->@*;
    ok(defined $arr, 'the list form still builds an ArrayLiteral') or return;
    is($arr->inputs->[0], $rl, 'the array holds the readline result');
};

# TEETH: the scalar readline binds exactly as its siblings do -- an SSA
# rebind and nothing else. This walker suppresses rpeep, so in production every
# scalar `my $x = ...` arrives as sassign, which declares nothing; a VarDecl
# here would make readline the only scalar binding carrying a wrapper.
subtest 'a scalar readline binding matches its siblings node-for-node' => sub {
    my $rl  = graph_of('sub { open(my $fh,"<","x"); my $s = <$fh>; $s }');
    my $eof = graph_of('sub { open(my $fh,"<","x"); my $s = eof($fh); $s }');

    my $decls = sub ($g) {
        return scalar grep { $_->operation eq 'VarDecl' } $g->nodes->@*;
    };
    is($decls->($rl), $decls->($eof),
        'readline emits the same number of VarDecls as eof (both zero)')
        or diag('readline ops = [' . ops_of($rl) . ']');

    ok(!grep({ $_->operation eq 'PadAccess' && ($_->symbol // '') eq 's' }
             $rl->nodes->@*),
        'no unbound PadAccess for $s is left in the graph')
        or diag('readline ops = [' . ops_of($rl) . ']');
};

done_testing();
