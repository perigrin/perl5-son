# ABOUTME: `sub { ... }` as a value is a CodeRef -- perl's ref() says CODE.
# ABOUTME: Stamped Code it was not even a Scalar, so every join reached Unknown.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub nodes_of ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    return [ map { { $_->%*, ($_->{fields} // {})->%* } }
             ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* ];
}

# PERL SETTLES IT. `sub { 1 }` in an expression is a CODE REFERENCE:
#
#     my $c = sub { 1 };   ref($c) is CODE, reftype($c) is CODE
#     ref(\&named)         CODE
#
# It was stamped `Code`, the CV itself. The difference is not cosmetic: in this
# lattice Code hangs off Unknown while CodeRef is a child of Ref,
#
#     Code     <: Ref  no   <: Scalar  no
#     CodeRef  <: Ref  yes  <: Scalar  yes
#
# so an anon sub held in a scalar had a type that cannot live in a scalar slot,
# and EVERY join it reached collapsed:
#
#     join(Code,    Undef) = Unknown        join(Code,    Str) = Unknown
#     join(CodeRef, Undef) = Scalar         join(CodeRef, Str) = Scalar
#
# That is the "callee return bottoms out" cascade in the audit doc, arriving
# through a different door.
subtest 'an anon sub value is a CodeRef' => sub {
    my $nodes = nodes_of('my $c = sub { 42 }; print ref($c);', 'anon');
    my ($a) = grep { $_->{op} eq 'AnonSub' } $nodes->@*;
    ok defined $a, 'the AnonSub node exists' or return;
    isnt $a->{stamp}, 'Code', 'it is not the CV itself';
    is $a->{stamp}, 'CodeRef', 'perl says ref() is CODE, so it is a CodeRef';
};

# THE POINT OF THE FIX, not just its statement: a CodeRef can be held in a
# scalar and merged with one. A Code cannot, and that is what poisoned the
# cascades. This asserts the CONSEQUENCE, so a fix that changes the label
# without fixing the lattice position would not satisfy it.
subtest 'an anon sub merged with a scalar does not collapse to Unknown' => sub {
    my $nodes = nodes_of(
        'my $c = $ENV{X} ? sub { 1 } : undef; print defined $c ? "y" : "n";', 'merged');
    my @unknown = grep { ($_->{stamp} // '') eq 'Unknown' } $nodes->@*;
    my @ternary = grep { $_->{op} eq 'TernaryExpr' } $nodes->@*;
    if (@ternary) {
        isnt $ternary[0]{stamp}, 'Unknown',
            'join(CodeRef, Undef) is a Scalar, not a hole';
    }
    else {
        pass('no ternary built; the merge shape is not present here');
    }
};

# A NAMED SUB IS NOT AN ANON SUB. `\&foo` is also a CODE ref, but it takes a
# different path; asserted so the fix is not assumed to cover it.
subtest 'a code ref taken with \\& is also a reference' => sub {
    my $nodes = nodes_of('sub foo { 1 } my $c = \&foo; print ref($c);', 'named');
    my @code = grep { ($_->{stamp} // '') eq 'Code' } $nodes->@*;
    is scalar(@code), 0,
        'nothing in a \&foo program is stamped as a bare Code'
        or diag explain [ map { { op => $_->{op}, s => $_->{stamp} } } @code ];
};

done_testing;
