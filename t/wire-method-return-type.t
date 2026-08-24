# ABOUTME: Tests the wire carries a return_type for class METHODS, as it does for subs.
# ABOUTME: A method's value is a bare graph-name string, so the type rides in a sibling map.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use JSON::PP;

# A plain sub's wire record is a hashref carrying return_type (B/SoN.pm:669,
# `_record_sub`). A METHOD's is a bare graph-name string (:888), because
# consumers in BOTH repos index the top-level {methods} graph map with it
# directly -- making it a hashref broke three producer tests and would have
# broken the chalk loader in lockstep.
#
# So a method's metadata rides in a SIBLING MAP keyed by the same method name.
# That pattern already exists for signatures (`method_signatures`) and is
# additive: an old consumer ignores the new key. `method_return_types` follows
# it exactly.
#
# WHY THIS MATTERS: measured before this landed, return_type was absent for 9
# of 9 class methods, so chalk's loader had no choice but to re-derive a
# method's return type by walking its graph
# (`_stamp_method_call_reprs`). For subs the loader's derivation is redundant
# with the wire; for methods it was the ONLY source. See chalk
# docs/plans/2026-08-24-loader-analysis-pipeline.md slice 2.

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($body, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nuse experimental 'class';\n"
              . "no warnings 'experimental::class';\n$body\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

subtest 'a method carries a return_type in the sibling map' => sub {
    my $wire = wire_for(
        'class P { method m { 42 } } my $o = P->new; print $o->m, "\n";',
        'int_method');
    my $c = $wire->{classes}{P} or return fail 'no class P on the wire';

    ok exists $c->{method_return_types},
        'the class record has a method_return_types map';
    is $c->{method_return_types}{m}, 'Int',
        'an Int-returning method is typed Int';

    # The methods map itself must be UNCHANGED -- a bare graph-name string.
    # Both repos index the top-level {methods} graph map with this value.
    is $c->{methods}{m}, 'P::m',
        'the methods map still holds a bare graph-name string';
};

subtest 'the type tracks what the method actually returns' => sub {
    my %CASES = (
        'class P { method m { "hi" } }'        => 'Str',
        'class P { method m { 1.5 } }'         => 'Num',
        'class P { method m { 1 == 1 } }'      => 'Boolean',
        'class P { method m { "a" . "b" } }'   => 'Str',
    );
    my $i = 0;
    for my $decl (sort keys %CASES) {
        $i++;
        my $wire = wire_for("$decl my \$o = P->new; print \$o->m, \"\\n\";",
                            "kind$i");
        is $wire->{classes}{P}{method_return_types}{m}, $CASES{$decl},
            "$decl -> $CASES{$decl}";
    }
};

subtest 'every method gets an entry, and Unknown is SENT not omitted' => sub {
    # Same discipline as the sub path: an absent field is not a type, and it
    # forces every consumer to invent a meaning. A method whose value carries
    # no stamp yet must say Unknown explicitly.
    my $wire = wire_for(
        'class P { method a { 5 } method b { $self->a } } '
        . 'my $o = P->new; print $o->b, "\n";',
        'multi');
    my $rt = $wire->{classes}{P}{method_return_types} // {};

    is [sort keys %$rt], [qw(a b)],
        'both methods have an entry';
    ok defined $rt->{$_}, "$_ has a defined type (never omitted)" for qw(a b);
};

subtest 'a generated :reader accessor is not a method record' => sub {
    # _record_sub deliberately does NOT emit a :reader CV as a sub, so nothing
    # shadows the synthesized accessor. The reader is a FIELD, and the field
    # already carries its own type -- so it must not appear here either.
    my $wire = wire_for(
        'class P { field $x :param :reader = 9; } my $o = P->new(x=>9); print $o->x, "\n";',
        'reader');
    my $rt = $wire->{classes}{P}{method_return_types} // {};
    ok !exists $rt->{x},
        'the :reader accessor is not listed as a method (it is a field)';
};

done_testing;
