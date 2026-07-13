# ABOUTME: The multiconcat decoder: dynamic .= and string interpolation build a
# ABOUTME: left-folded Concat chain (zhi 019ee838). Const-append (nargs==0) was 4b-4b.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# perl emits a `multiconcat` UNOP_AUX for `$s .= $t` (dynamic APPEND) and for
# interpolation `qq{$a$b}` / `qq{p-$a-m-$b-q}`. aux_list = [nargs, plain_pv,
# seglen_0 .. seglen_nargs]; plain_pv is all const segments concatenated flat,
# sliced by the seglens (a seglen of -1 is an empty segment). The decode is
# result = seg[0] . arg[0] . seg[1] . arg[1] . ... . seg[nargs], built as a
# left-folded chain of binary Concat nodes over the dynamic operands (which the
# preceding padsv ops pushed) interleaved with Str Constants for the segments.

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub op_counts ($graph) {
    my %n;
    $n{ $_->operation }++ for $graph->nodes->@*;
    return \%n;
}

subtest 'dynamic append $s .= $t builds a Concat over the operand' => sub {
    my $g = translate('sub { my $s = "a"; my $t = "b"; $s .= $t; $s }');
    ok(defined $g, 'translates (no GAP)');
    my $c = op_counts($g);
    ok($c->{Concat} && $c->{Concat} >= 1, 'has a Concat node') or diag(join(',', sort keys %$c));
};

subtest 'interpolation qq{$a$b} builds a Concat chain of the two operands' => sub {
    my $g = translate('sub { my $a = "x"; my $b = "y"; my $c = "$a$b"; $c }');
    ok(defined $g, 'translates (no GAP)');
    my $c = op_counts($g);
    # arg0 . arg1 = one Concat (no segments).
    ok($c->{Concat} && $c->{Concat} >= 1, 'has a Concat node') or diag(join(',', sort keys %$c));
};

subtest 'interpolation with const segments interleaves Str constants' => sub {
    my $g = translate('sub { my $a = "x"; my $b = "y"; my $c = "p-$a-m-$b-q"; $c }');
    ok(defined $g, 'translates (no GAP)');
    my $c = op_counts($g);
    # "p-" . arg0 . "-m-" . arg1 . "-q" = 4 Concats over 3 Str-const segments + 2 args.
    ok($c->{Concat} && $c->{Concat} >= 3, 'has a folded Concat chain (>=3)')
        or diag(join(',', sort keys %$c));
    ok($c->{Constant} && $c->{Constant} >= 3, 'has the segment Str constants')
        or diag(join(',', sort keys %$c));
};

done_testing();
