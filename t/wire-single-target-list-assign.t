# ABOUTME: `my ($x) = @_` is a LIST assignment, not a scalar one -- shape, not arity.
# ABOUTME: With one target it has two inputs and was taking the RHS's Array stamp.
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
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
    my $w = ($out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return [] unless $w;
    return [ map { $_->{nodes}->@* }
             map { $w->{methods}{$_} }
             grep { !/__PROGRAM__/ } keys $w->{methods}->%* ];
}

# A LIST ASSIGNMENT YIELDS ITS RHS COUNT IN SCALAR CONTEXT, measured:
#
#     my $n = (my ($y) = @_);   with @_ = (5,6,7)   $n is 3
#
# and the TARGET gets one element, never the array:
#
#     sub p { my ($x) = @_ }    p(5) -> Int, p("s") -> Str, p(5,6,7) -> Int
#
# _floor_list_assigns already documents exactly this and floors the node at
# join(Int, List). But it keys the LIST SHAPE on `@in > 2` -- several targets
# plus an RHS -- and `my ($x) = @_` has just TWO inputs, so it read as a scalar
# assign and kept the RHS's stamp:
#
#     Assign(PadAccess $x, ArgsSource)  stamp=Array
#
# The slot is a SCALAR. The graph said the scalar slot holds an array.
#
# ARITY IS THE WRONG DISCRIMINATOR, which is the same mistake this project has
# made before with map-body contributions: `my ($x) = @_` and `my $x = shift`
# differ in SHAPE (list assign vs scalar assign), not in how many nodes they
# happen to carry.

subtest 'a single-target list assign is not stamped Array' => sub {
    my $n = nodes_of('sub p { my ($x) = @_; return $x + 1 } print p(5);', 'sl-one');
    my ($as) = grep { $_->{op} eq 'Assign' } $n->@*;
    ok $as, 'the assignment is built' or return;
    isnt $as->{stamp}, 'Array',
        'it does not claim the scalar slot holds the whole @_';
};

# THE MULTI-TARGET FORM ALREADY WORKED and must be undisturbed -- it is what
# the `@in > 2` test was written for.
subtest 'a multi-target list assign is unchanged' => sub {
    my $n = nodes_of('sub q2 { my ($x,$y) = @_; return $x + $y } print q2(1,2);',
                     'sl-two');
    my ($as) = grep { $_->{op} eq 'Assign' } $n->@*;
    ok $as, 'the assignment is built' or return;
    isnt $as->{stamp}, 'Array', 'still not Array';
};

# A GENUINE SCALAR ASSIGN MUST KEEP ITS RHS TYPE. `$a[0] = "foo"` is Assign:Str
# -- strictly more precise than any floor -- and the pass's own comment says
# flooring one would "win a race it has no business winning".
subtest 'a scalar assign still takes its RHS type' => sub {
    my $n = nodes_of('sub r { my @a=(1); $a[0] = "foo"; return $a[0] } print r();',
                     'sl-scalar');
    my ($as) = grep { $_->{op} eq 'Assign' } $n->@*;
    ok $as, 'the assignment is built' or return;
    is $as->{stamp}, 'Str', 'Str from the RHS, not floored';
};

# THE READS WERE ALWAYS RIGHT. Backward inference types $x from its use, so
# this was never a wrong answer reaching a consumer -- it was a wrong stamp on
# the assignment node itself.
subtest 'the read of the target is typed from its use' => sub {
    my $n = nodes_of('sub s2 { my ($x) = @_; return $x . "!" } print s2("a");',
                     'sl-read');
    my ($pad) = grep { $_->{op} eq 'PadAccess' } $n->@*;
    ok $pad, 'the $x read exists' or return;
    is $pad->{stamp}, 'Str', 'Str from `$x . "!"`';
};

done_testing;
