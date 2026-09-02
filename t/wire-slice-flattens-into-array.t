# ABOUTME: An array built from a slice has unknown arity -- its elements are not countable.
# ABOUTME: `my @t = @_[-2,-1]` is 2 elements from ONE ArrayLiteral input.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub nodes_of ($src, $name, $meth = 'main::__PROGRAM__') {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    return [ map { { $_->%*, ($_->{fields} // {})->%* } }
             ($wire->{methods}{$meth}{nodes} // [])->@* ];
}

# A SLICE FLATTENS. `my @t = @_[-2,-1]` builds ArrayLiteral(Slice) -- ONE input
# holding TWO elements. _literal_element_type counts INPUTS, so it read the
# array as 1-element and answered from that:
#
#     $t[1]   index 1 > $#elems(0)  ->  'Undef'   MISCOMPILE, perl gives 4
#     $t[0]   element 0's stamp     ->  'List'    wrong in KIND -- one slot
#                                                 of an array is a scalar
#
# The arity, not the type, is the undecidable thing: an input stamped List
# stands for an unknown NUMBER of elements, so neither the bounds check nor the
# element join applies. This is the same lesson as the earlier map/grep fix --
# the discriminating property is arity.
#
# `sub f { my @t = @_[-2,-1]; ... } f(1,2,3,4)` prints "3,4" under perl.
my $SRC = 'sub f { my @t = @_[-2, -1]; return "$t[0],$t[1]" } print f(1,2,3,4);';

subtest 'a read past a flattened slice is not claimed Undef' => sub {
    my $nodes = nodes_of($SRC, 'negslice', 'main::f');
    my @subs = grep { $_->{op} eq 'Subscript' } $nodes->@*;
    ok scalar(@subs) >= 2, 'both element reads exist' or return;
    for my $s (@subs) {
        isnt $s->{stamp}, 'Undef',
            'a slice-fed array is not read as out of bounds';
    }
};

# ONE SLOT OF AN AGGREGATE IS A SCALAR. Never List, never Array -- there is no
# program in which a subscript is plural, which is why Slice is a different
# node kind. Stamping a slot List is wrong in kind, not merely wide.
subtest 'a slot of a slice-fed array is never plural' => sub {
    my $nodes = nodes_of($SRC, 'negslice_kind', 'main::f');
    my @subs = grep { $_->{op} eq 'Subscript' } $nodes->@*;
    ok scalar(@subs) >= 2, 'both element reads exist' or return;
    for my $s (@subs) {
        isnt $s->{stamp}, 'List', 'one slot is not a list';
        isnt $s->{stamp}, 'Array', 'one slot is not an array';
    }
};

# THE ORDINARY LITERAL MUST STILL NARROW. This is the guard that a fix does not
# simply switch off element typing: a plain literal array has countable inputs
# and its bounds and element join both still apply.
subtest 'a plain literal array still narrows and still bounds-checks' => sub {
    my $nodes = nodes_of('my @a = (1,2,3); print $a[1];', 'plainarr');
    my ($sub) = grep { $_->{op} eq 'Subscript' } $nodes->@*;
    ok defined $sub, 'the read exists' or return;
    is $sub->{stamp}, 'Int', 'an all-Int literal array still reads Int';

    my $oob = nodes_of('my @a = (1,2); print $a[5];', 'plainoob');
    my ($osub) = grep { $_->{op} eq 'Subscript' } $oob->@*;
    ok defined $osub, 'the out-of-range read exists' or return;
    is $osub->{stamp}, 'Undef', 'a provably out-of-range index is still Undef';
};

done_testing;
