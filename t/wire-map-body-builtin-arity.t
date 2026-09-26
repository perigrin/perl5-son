# ABOUTME: A map body calling a SCALAR builtin contributes exactly one value.
# ABOUTME: The allow-list was keyed on node kind, so every Call was refused.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;
use SoN::Deparse;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub run_and_wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $said = qx{$PERL $file 2>/dev/null};
    my $out  = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    return ($said, $out, $err);
}

# THE PROPERTY IS ARITY, NOT NODE KIND -- which the existing allow-list says,
# and then keys on node kind anyway. Every builtin becomes a `Call`, so `lc`
# was swept up with genuinely variadic calls and refused:
#
#     map { lc($_) } ("A","B")     GAP: a Call may yield more than one value
#
# `lc` yields exactly one value, always. Measured across the family -- lc, uc,
# lcfirst, ucfirst, abs, int, sqrt, ord, chr, hex, oct, log, exp, cos, sin,
# quotemeta all yield 1, while reverse, sort and split yield N.
#
# A CALL THROUGH A CODEREF STAYS REFUSED, and correctly: `map { &{$sub}($_) }`
# in perl's own t/comp/proto.t calls a sub nobody can name at compile time, so
# its arity is genuinely unknowable. That is the case the GAP exists for.

# ASSERTS THE COUNT, NOT JUST THE ABSENCE OF A GAP. "it did not refuse" is
# satisfied by a graph that appends the wrong number of values, which is the
# exact miscompile the allow-list exists to prevent -- so the shape is checked:
# the ListAppend must carry the accumulator plus ONE contribution.
subtest 'the appended contribution is exactly one value' => sub {
    my ($said, $out, $err) = run_and_wire(
        'my @m = map { lc($_) } ("A","B"); print scalar(@m);', 'map-shape');
    is $said, '2', 'perl yields two values' or return;
    unlike $err, qr/unknown arity/, 'it lowers' or return;

    my $w = eval { JSON::PP->new->decode($out =~ s/\A[^{]*//sr) };
    ok $w, 'the wire parses' or return;
    my ($la) = grep { $_->{op} eq 'ListAppend' }
               map { $_->{nodes}->@* } values $w->{methods}->%*;
    ok $la, 'a ListAppend is built' or return;
    is scalar(($la->{inputs} // [])->@*), 2,
        'accumulator + exactly ONE contribution -- not a node standing for N';
};

subtest 'a scalar builtin in a map body lowers' => sub {
    for my $b ('lc($_)', 'uc($_)', 'abs($_)', 'int($_)', 'ord($_)') {
        my ($said, $out, $err) = run_and_wire(
            "my \@m = map { $b } (1,2); print scalar(\@m);", "map-$b" =~ s/\W//gr);
        is $said, '2', "perl maps two values through $b";
        unlike $err, qr/unknown arity/, "... and $b no longer refuses";
    }
};

# THE VARIADIC ONES LOWER TOO, AND NOBODY MISCOUNTS. The refusal's premise was
# that "appending one node that STANDS FOR N makes a consumer counting inputs
# read 1" -- a claim about a CONSUMER, which is testable and turned out false
# for ours. Measured on `map { reverse($_,$_) } (5,6)`:
#
#     my @phi4_next = (@phi4, reverse((5,6)[$i], (5,6)[$i]));
#     print scalar(@phi4);
#
# The count is `scalar(@phi4)` -- a RUNTIME count of the accumulated array, not
# an input count of the ListAppend. perl does the flattening, exactly as it does
# in the source. The hypothetical input-counting consumer does not exist here,
# and a T2 backend that needs the arity declines the node kind rather than
# having T1 refuse for it.
#
# ASSERTED BY RUNNING THE EMISSION. The previous form of these subtests checked
# only that a GAP appeared, which cannot tell "the refusal is necessary" from
# "the refusal is habitual".
subtest 'a list-yielding builtin lowers and counts right' => sub {
    for my $b ('reverse($_,$_)', 'sort($_,$_)') {
        my $tag = "mapv-$b" =~ s/\W//gr;
        my ($said, $out, $err) = run_and_wire(
            "my \@m = map { $b } (5,6); print scalar(\@m);", $tag);
        is $said, '4', "perl yields four values through $b" or next;
        unlike $err, qr/unknown arity/, "... and $b no longer refuses" or next;

        my $g = eval { JSON::PP->new->decode($out) } or do {
            fail "$b: the wire parses"; next;
        };
        my $emitted = eval {
            SoN::Deparse->new->render($g);
        };
        ok defined $emitted, "$b renders" or do { diag $@; next };

        my $ef = "$dir/$tag-emit.pl";
        open my $efh, '>', $ef or die $!;
        print {$efh} $emitted;
        close $efh;
        is qx{$PERL $ef 2>&1}, '4', "... and the emitted program counts 4 too"
            or diag $emitted;
    }
};

# A CALL TO A USER SUB LOWERS, and its arity is STILL not on the wire -- which
# is the point. `sub g {42}` yields 1 and `sub g { ($_[0],$_[0]) }` yields 2
# from an identical callsite, and neither needs to be known here, because the
# emission defers the flattening to perl.
subtest 'a user sub call lowers whatever its arity' => sub {
    for my $pair ( [ 'sub g { 42 }', '2' ],
                   [ 'sub g { ($_[0],$_[0]) }', '4' ] ) {
        my ( $decl, $want ) = $pair->@*;
        my $tag = 'map-user-' . length($decl);
        my ($said, $out, $err) = run_and_wire(
            "$decl my \@m = map { g(\$_) } (5,6); print scalar(\@m);", $tag);
        is $said, $want, "perl says $want for `$decl`" or next;
        unlike $err, qr/unknown arity/, "... and it no longer refuses" or next;

        my $g = eval { JSON::PP->new->decode($out) } or do {
            fail "the wire parses"; next;
        };
        my $emitted = eval { SoN::Deparse->new->render($g) };
        ok defined $emitted, 'renders' or do { diag $@; next };

        my $ef = "$dir/$tag-emit.pl";
        open my $efh, '>', $ef or die $!;
        print {$efh} $emitted;
        close $efh;
        is qx{$PERL $ef 2>&1}, $want, "... and the emission says $want too"
            or diag $emitted;
    }
};

done_testing;
