# ABOUTME: map/grep build a list whose length is not the input's.
# ABOUTME: ListAppend is the loop-carried accumulator that makes that expressible.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub run_and_translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $out  = qx{$PERL $file 2>/dev/null};
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# WHY THIS NEEDED NEW VOCABULARY. map and grep are loops -- measured, they carry
# mapwhile/grepwhile exactly as `while` carries enterloop/leaveloop -- so the
# loop machinery applies. But the loop machinery had no ACCUMULATOR, and map's
# output length is not its input length:
#
#     map { ($_, $_) } (1,2)   -> 4 elements
#     map { () } (1,2)         -> 0 elements
#     grep { $_ > 1 } (1,2,3)  -> 2 elements
#
# Count(list) bounds the INPUT; nothing bounded the output. ListAppend is the
# loop-carried value that does: it takes the accumulator so far plus whatever
# this iteration produced, and yields the new accumulator. The existing loop-Phi
# machinery carries it across the back-edge like any other loop-carried value.
subtest 'grep filters and the graph says how' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my @g = grep { $_ > 1 } (1,2,3); print scalar(@g);', 'grep' );
    is $out, '2', 'perl keeps two' or return;
    ok $w, 'it translates rather than GAPping' or diag($err), return;

    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
    ok scalar( grep { $_ eq 'ListAppend' } @ops ),
        'and a ListAppend accumulator';
};

# THE ACCUMULATOR MUST BE LOOP-CARRIED, not rebuilt each pass: its previous
# value has to reach it through the loop Phi, or the result is one iteration's
# output rather than all of them.
subtest 'the accumulator is carried across the back-edge' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'my @g = grep { $_ > 1 } (1,2,3); print scalar(@g);', 'grep-phi' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($app) = grep { ( $_->{op} // '' ) eq 'ListAppend' } $ns->@*;
    ok $app, 'a ListAppend exists' or return;

    my @in = map { $by{$_} } ( $app->{inputs} // [] )->@*;
    ok scalar( grep { ( $_->{op} // '' ) eq 'Phi' } @in ),
        'its accumulator input is a loop Phi';
};

# map APPENDS THE BODY VALUE, which is what distinguishes it from grep: grep
# appends the ELEMENT when the body is true, map appends the body's own result.
subtest 'map appends the body value' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my @m = map { $_ * 2 } (1,2); print "@m";', 'map' );
    is $out, '2 4', 'perl doubles each' or return;
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($app) = grep { ( $_->{op} // '' ) eq 'ListAppend' } $ns->@*;
    ok $app, 'a ListAppend exists' or return;

    my @in = map { $by{$_} } ( $app->{inputs} // [] )->@*;
    ok scalar( grep { ( $_->{op} // '' ) eq 'Multiply' } @in ),
        'the appended value is the body result, not the raw element';
};

# THE TYPE OF A LIST IS List. The input list a map/grep iterates is built by
# the same ArrayLiteral every other list site uses, and every one of THOSE
# stamps explicitly -- `my @a = (1,2,3)` is Array, `[1,2,3]` is ArrayRef. Left
# unstamped this site fell through to Unknown, the lattice TOP, which asserts
# nothing about a value whose type is known at construction: a literal list is
# a List, and List is a real member sitting directly under Unknown with
# Array/Hash/Scalar beneath it.
#
# Unknown here is not merely imprecise. It is the one stamp that makes a
# consumer unable to tell a list from a code ref, so it must not be what a
# LITERAL LIST carries.
subtest 'the list a map iterates is stamped List, not Unknown' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'my @m = map { $_ * 2 } (1,2); print "@m";', 'map-stamp' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;

    # The iterated list is what Count bounds: that is the loop's input, as
    # distinct from the empty ArrayLiteral seeding the accumulator.
    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $ns->@*;
    ok $count, 'a Count bounds the loop' or return;
    my $input = $by{ ( $count->{inputs} // [] )->[0] // '' };
    ok $input, 'and it counts something' or return;

    is $input->{op}, 'ArrayLiteral', 'the counted value is the literal list';
    is $input->{stamp}, 'List', '... stamped List';
};

# A HASH IN A map BODY FLATTENS TO ITS KEY/VALUE PAIRS. The body runs in LIST
# context (measured: `map { wantarray } (1)` yields LIST), so an aggregate left
# there contributes ALL its elements, not itself:
#
#     my %h=(a=>1,b=>2); my @m = map { %h } (1);   -> 4 elements
#     my @b=(7,8);       my @m = map { @b } (1,2); -> 4 elements
#
# The array form already flattened correctly -- the walk pops the elements. The
# hash form appended the HashLiteral CONTAINER as a single input, so a consumer
# counting inputs read 1 where perl says 4. Same class as the aggregate
# double-wrap at the assignment site, one type over: a container is not an
# element, and "a List is not an Array".
subtest 'an aggregate in a map body contributes its elements, not itself' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my %h=(a=>1,b=>2); my @m = map { %h } (1); print scalar(@m);',
        'map-hash-flatten' );
    is $out, '4', 'perl flattens the hash to four values' or return;

    # REFUSED, not lowered. A hash's pair count is a runtime property, so
    # there is no honest static arity to append -- and appending the
    # container instead made a consumer counting inputs read 1 for perl's 4.
    # A GAP is the correct answer here; a wrong count is not.
    like $err, qr/GAP/,
        'B::SoN refuses rather than appending the container as one element';

    my $ns  = $w ? nodes($w) : [];
    my @app = grep { ( $_->{op} // '' ) eq 'ListAppend' } $ns->@*;
    is scalar(@app), 0, '... and emits no ListAppend for it';
};

# THE ARRAY FORM STILL LOWERS. The refusal above must not swallow the case
# that already flattened correctly: the walk pops an array's elements
# individually, so they arrive as separate contributions and the count is
# right. A fix that refused both would be a regression dressed as caution.
subtest 'an array in a map body still flattens and lowers' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my @b=(7,8); my @m = map { @b } (1,2); print scalar(@m);',
        'map-array-flatten' );
    is $out, '4', 'perl flattens the array to four values' or return;
    ok $w, 'it still translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($app) = grep { ( $_->{op} // '' ) eq 'ListAppend' } $ns->@*;
    ok $app, 'a ListAppend exists' or return;

    my @ids = ( $app->{inputs} // [] )->@*;
    shift @ids;    # inputs[0] is the accumulator, not a contribution
    is scalar(@ids), 2,
        'two contributions per iteration, matching the array length';
};

# A SLICE IS ALSO A MULTI-VALUE CONTRIBUTION, and the stamp does not say so.
# `@h{qw(a b)}` yields 2 values, but arrives as ONE Slice node stamped Unknown,
# so a refusal keyed on the Hash/Array stamps walks straight past it and appends
# it as a single element -- 1 where perl says 2. Same class as the hash body,
# but invisible to a stamp test, which is why this is keyed on the NODE KIND.
#
# Unlike a hash, a slice's arity IS static (2 keys, 2 values). It is refused
# rather than lowered only because nothing yet splits one into its elements;
# that is a lowering waiting to happen, not an impossibility.
subtest 'a slice in a map body is not appended as one element' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my %h=(a=>1,b=>2); my @m = map { @h{qw(a b)} } (1); print scalar(@m);',
        'map-hash-slice' );
    is $out, '2', 'perl yields the two sliced values' or return;

    like $err, qr/GAP/,
        'B::SoN refuses rather than appending the slice as one element';

    my $ns  = $w ? nodes($w) : [];
    my @app = grep { ( $_->{op} // '' ) eq 'ListAppend' } $ns->@*;
    is scalar(@app), 0, '... and emits no ListAppend for it';
};

# GREP IS ARITY-PRESERVING ON ITS INPUT and must NOT be caught by any of the
# refusals above. Its body is a predicate read in boolean context -- `%h` there
# is truthiness, never flattened -- so its contribution is structurally 0-or-1
# whatever the body evaluates to. A refusal keyed on the contribution's shape
# would turn a correct grep into a false GAP, which is the same
# regression-dressed-as-caution the array subtest guards against, one op over.
subtest 'grep with an aggregate body still lowers' => sub {
    for my $case (
        [ 'my %h=(a=>1,b=>2); my @g = grep { %h } (1,2); print scalar(@g);',
          '2', 'hash' ],
        [ 'my @b=(7,8); my @g = grep { @b } (1,2,3); print scalar(@g);',
          '3', 'array' ],
    ) {
        my ( $src, $want, $label ) = $case->@*;
        my ( $out, $w, $err ) = run_and_translate( $src, "grep-agg-$label" );
        is $out, $want, "perl keeps all $want ($label body)";
        ok $w, "... and B::SoN still lowers it ($label)" or diag($err);
    }
};

# THE DISCRIMINATING PROPERTY IS ARITY, NOT IDENTITY. This miscompile was
# fixed twice by naming node properties, and each name turned out not to be the
# one that separated the cases:
#
#   keyed on STAMP (Hash/Array)     -- missed Slice, stamped Unknown
#   keyed on NODE KIND (+Slice)     -- missed reverse/sort, which are Calls
#
# Every member is just "contributes != 1 value", and an enumeration of kinds is
# a proxy for that which keeps being incomplete -- silently, each time. So the
# walk now uses an ALLOW-LIST: a contribution is accepted only when its node
# kind is KNOWN to yield exactly one value. Anything else refuses.
#
# That fails safe rather than silent. The cost is GAPping shapes that would
# have been fine; the benefit is that a new list-producing node kind arrives as
# a refusal instead of a wrong count.
subtest 'a list-producing builtin in a map body does not miscount' => sub {
    for my $case (
        [ 'my @a=(1,2,3); my @m = map { reverse @a } (1); print scalar(@m);',
          '3', 'reverse' ],
        [ 'my @a=(3,1,2); my @m = map { sort @a } (1); print scalar(@m);',
          '3', 'sort' ],
    ) {
        my ( $src, $want, $label ) = $case->@*;
        my ( $out, $w, $err ) = run_and_translate( $src, "map-builtin-$label" );
        is $out, $want, "perl flattens $label to $want values";

        # Either it refuses, or it appends the right NUMBER of contributions.
        # What it must never do is append one value standing for N.
        my $ns  = $w ? nodes($w) : [];
        my ($app) = grep { ( $_->{op} // '' ) eq 'ListAppend' } $ns->@*;
        if ($app) {
            my @ids = ( $app->{inputs} // [] )->@*;
            shift @ids;
            is scalar(@ids), $want,
                "... and $label appends $want contributions, not 1";
        }
        else {
            like $err, qr/GAP/, "... and $label refuses rather than miscounting";
        }
    }
};

# A MIXED CONTRIBUTION is neither N nor 1: `map { %h, 9 }` over a 2-pair hash
# yields 5 (four from the hash, one scalar). Named separately because an
# arity rule that handles the pure-aggregate case can still get this wrong.
subtest 'a mixed aggregate/scalar body does not miscount' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my %h=(a=>1,b=>2); my @m = map { %h, 9 } (1); print scalar(@m);',
        'map-mixed' );
    is $out, '5', 'perl yields four from the hash plus one scalar' or return;
    like $err, qr/GAP/, 'B::SoN refuses rather than miscounting';
};

# THE ALLOW-LIST MUST NOT SWALLOW THE ORDINARY CASES. Every shape that
# genuinely contributes one value per iteration has to keep lowering, or the
# fix is a regression dressed as caution -- the same failure mode, a third time.
subtest 'single-value bodies still lower under the allow-list' => sub {
    for my $case (
        [ 'my @m = map { $_ * 2 } (1,2); print "@m";',        '2 4',  'arith' ],
        [ 'my @m = map { $_ } (1,2); print "@m";',            '1 2',  'ident' ],
        [ 'my @m = map { 7 } (1,2); print "@m";',             '7 7',  'const' ],
        [ 'sub g { 7 } my @m = map { g() } (1,2); print "@m";','7 7',  'call'  ],
        [ 'my @a=(5,6); my @m = map { $a[0] } (1,2); print "@m";','5 5','elem' ],
        [ 'my @m = map { (1,2) } (1); print scalar(@m);',     '2', 'literal-list' ],
    ) {
        my ( $src, $want, $label ) = $case->@*;
        my ( $out, $w, $err ) = run_and_translate( $src, "map-ok-$label" );
        is $out, $want, "perl: $label";
        ok $w, "... and B::SoN still lowers it ($label)" or diag($err);
    }
};

done_testing;
