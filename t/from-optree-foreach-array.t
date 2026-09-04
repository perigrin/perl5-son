# ABOUTME: Tests SoN::FromOptree lowers a foreach over a lexical ARRAY (not a
# ABOUTME: range) to a counted loop over the array's elements. zhi 019f5da9.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

# `for my $x (@a) { $s += $x }` iterates each element of @a. Unlike the range
# foreach (1..N, counted with synthesized bounds), an array foreach is bounded
# by the array's length and binds $x to element[i] each pass. `for` and
# `foreach` are aliases -- the same enteriter optree -- so both spellings lower
# identically.

subtest 'foreach over an array translates to a Loop (does not GAP)' => sub {
    my $g;
    ok(lives { $g = translate('sub { my @a=(10,20,30); my $s=0; for my $x (@a) { $s += $x } $s }') },
        'foreach-over-array translates') or diag($@);
    ok(defined $g, 'got a graph') or return;
    my @loops = grep { $_->operation eq 'Loop' } $g->nodes->@*;
    is(scalar(@loops), 1, 'exactly one Loop node') or diag($renderer->render($g));
};

subtest 'the foreach keyword is an alias of for (same lowering)' => sub {
    my $g_for     = translate('sub { my @a=(1,2); my $s=0; for my $x (@a) { $s += $x } $s }');
    my $g_foreach = translate('sub { my @a=(1,2); my $s=0; foreach my $x (@a) { $s += $x } $s }');
    is($renderer->render($g_foreach), $renderer->render($g_for),
        'for and foreach produce an identical graph');
};

# Perl's `for my $x (@a)` ALIASES $x to each element, so a body write `$x = ...`
# mutates @a in place -- measured, `for my $x (@a) { $x = $x*10 }` leaves @a as
# 10 20 30. The lowering binds $x to an element COPY, so the write needs an
# explicit store-back; without one it was silently lost, and it GAPed instead.
#
# LOWERED as the element store that already exists: `$a[0]=99` builds a 2-input
# lvalue Subscript and an Assign, and this is that shape with the loop's index
# Phi as the subscript.
subtest 'a foreach body that writes the iterator stores back' => sub {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval 'sub { my @a=(10,20); for my $x (@a) { $x = $x + 1 } $a[0] }';
    SoN::OptSuppress::restore_peep();

    my $g;
    ok(lives { $g = SoN::FromOptree->translate($cv) },
        'an iterator-write foreach body lowers') or diag($@);
    return unless $g;

    # The store-back is an Assign over a Subscript lvalue.
    my ($store) = grep {
        $_->operation eq 'Assign'
          && ($_->inputs->[0] // undef)
          && $_->inputs->[0]->operation eq 'Subscript'
    } $g->nodes->@*;
    ok($store, 'an element store-back is built');
};

done_testing;
