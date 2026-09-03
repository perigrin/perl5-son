# ABOUTME: An array read in SCALAR context is its element count, even with no
# ABOUTME: `scalar` op -- perl folds that op away in a sub's trailing position.
use 5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# SUPPRESS AT RUNTIME, NOT IN BEGIN. Calling suppress_peep() from a BEGIN
# block disables the peephole optimizer while THIS FILE is still compiling, so
# the test's own optree is built without it -- measured, that segfaults perl
# (exit 139) the moment Graph::nodes walks a translated graph. Every other test
# in this suite calls it at runtime for the same reason.
sub return_input ($cv) {
    SoN::OptSuppress::suppress_peep();
    my $g = SoN::FromOptree->translate($cv);
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    return undef unless $ret;
    my @in = $ret->inputs->@*;
    return @in ? $in[0]->operation : undef;
}

# AN ARRAY IN SCALAR CONTEXT IS ITS COUNT, and the `scalar` OP IS NOT THE
# SIGNAL. Measured on 5.42.0 -- the same source compiles two ways depending on
# position:
#
#     sub named { my @a=(1,2,3); scalar @a }   padav(f=0x2) scalar(f=0x6)
#     sub       { my @a=(1,2,3); scalar @a }   padav(f=0x2)          <- gone
#
# In a sub's TRAILING position perl folds the `scalar` op away, leaving only a
# padav whose OPf_WANT is SCALAR. Keying on the op meant the trailing form fell
# through to the aggregate and the sub returned the ARRAY where perl returns 3.
#
# THE WANT FLAG IS THE SIGNAL, and it separates the cases cleanly:
#
#     scalar @a / my $n = @a / if (@a)   f=0x02  want=SCALAR  no REF|MOD
#     for my $x (@a)                     f=0x32  want=SCALAR  REF|MOD
#     trailing @a (list return)          f=0x00  want=VOID/list
#
# so a scalar read is want==2 with neither REF|MOD nor LVAL_INTRO.
subtest 'a trailing scalar read of an array returns its count' => sub {
    is return_input(sub { my @a=(1,2,3); scalar @a }), 'Count',
        'sub { ...; scalar @a } returns a Count, not the array';
};

subtest 'the same holds through a scalar assignment' => sub {
    is return_input(sub { my @a=(1,2,3); my $n = @a; $n }), 'Count',
        'my $n = @a is a Count';
};

# A LIST RETURN IS NOT A COUNT. `sub { @a }` genuinely returns the array, and a
# fix that counted every trailing array read would turn every list-returning
# sub into a number -- trading one silent wrong answer for another.
subtest 'a trailing list read still returns the aggregate' => sub {
    my $got = return_input(sub { my @a=(1,2,3); @a });
    isnt $got, 'Count',
        'sub { ...; @a } does NOT become a Count';
};

# A FOREACH SOURCE IS NOT A COUNT EITHER. It is want=SCALAR like the read
# above, and REF|MOD is what separates them -- keying on want alone would
# iterate over the number 3.
subtest 'a foreach source is not counted' => sub {
    SoN::OptSuppress::suppress_peep();
    my $g = SoN::FromOptree->translate(
        sub { my @a=(1,2,3); my $t=0; for my $x (@a) { $t += $x } $t });
    ok defined $g, 'a foreach over an array still translates';
};

done_testing;
