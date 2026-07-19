# ABOUTME: print LISTOP builds a Print node (op 'Print') over its whole arg
# ABOUTME: list, control-pinned; explicit-filehandle and coerce-needing forms GAP.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Translate a code string under rpeep suppression (the production -MO=SoN path)
# and return the graph, or die on GAP/compile error.
sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

sub prints ($g) {
    return grep { $_->operation eq 'Print' } $g->nodes->@*;
}

sub is_effect ($n) {
    return defined $n->control_in;
}

# --- 1. a bare literal-list print builds ONE Print node over ALL its args ---
subtest 'print of a literal list -> Print node with every element' => sub {
    my $g = translate('sub { print "ok ", 1, "\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'exactly one Print node') or diag(
        'ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
    my $p = $p[0];

    # inputs lead with the control token (is_stmt_effect); the remaining inputs
    # are the three list elements ("ok ", 1, "\n").
    ok(is_effect($p), 'Print is a statement effect (control-pinned)');
    my @vals = grep { $_->operation eq 'Constant' } $p->inputs->@*;
    is(scalar @vals, 3, 'all three list elements are inputs to Print')
        or diag('inputs = [' . join(' ', map { $_->operation } $p->inputs->@*) . ']');
};

# --- 2. single-arg print ---
subtest 'print of a single string -> Print node' => sub {
    my $g = translate('sub { print "hi\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'one Print node');
    ok(is_effect($p[0]), 'control-pinned');
};

# --- 3. two prints stay two distinct, ordered effects ---
subtest 'two prints -> two Print effects on the control chain' => sub {
    my $g = translate('sub { print "a\n"; print "b\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 2, 'two Print nodes, neither dropped')
        or diag('ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
};

# --- 4. R1.5 LOUD GAP: print to an explicit filehandle (OPf_STACKED) ---
subtest 'print STDOUT ... is a loud GAP, never a silent fd-1 misroute' => sub {
    my $err = dies { translate('sub { print STDOUT "x\n"; 1 }') };
    like($err, qr/GAP.*filehandle/i,
        'print to an explicit filehandle dies with a GAP naming the filehandle');
};

subtest 'print $fh ... is a loud GAP' => sub {
    my $err = dies { translate('sub { my $fh; print $fh "x\n"; 1 }') };
    like($err, qr/GAP.*filehandle/i, 'print to a lexical filehandle GAPs loudly');
};

# --- 5. interpolated print: the multiconcat arg decodes to a runtime-free
# Concat, so print emits it as a Print over that one value (NOT dropped). ---
subtest 'interpolated print -> Print over the concatenated value' => sub {
    my $g = translate('sub { my $n = 1; print "ok $n\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'one Print node, arg not dropped')
        or diag('ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
    ok(is_effect($p[0]), 'control-pinned');
};

done_testing;
