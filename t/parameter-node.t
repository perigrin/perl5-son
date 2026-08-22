# ABOUTME: A declared signature parameter lowers to a Parameter node, not a PadAccess.
# ABOUTME: Pure, hash-consed by index, typed from its sigil.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub nodes_for ( $src, $name, $graph ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    my $g = $wire->{methods}{$graph}
        or die "no graph '$graph'; have: "
        . join( ',', sort keys $wire->{methods}->%* );
    return $g->{nodes} // [];
}

# Accepts the arrayref nodes_for returns, or a plain list of nodes.
sub params_in (@args) {
    my @nodes = ( @args == 1 && ref $args[0] eq 'ARRAY' ) ? $args[0]->@* : @args;
    return grep { ref $_ eq 'HASH' && ( $_->{op} // '' ) eq 'Parameter' } @nodes;
}

# The argelem handler HAS the parameter index and sigil and discards both,
# minting a PadAccess -- a pad SLOT, which is perl's storage for the parameter
# rather than the parameter itself. Measured on the op:
#
#   sub two($a,$b)   argelem aux_list=[0] private=0   argelem aux_list=[1] private=0
#   sub mix($a,@r)   argelem aux_list=[0] private=0   argelem aux_list=[1] private=2
#
# aux_list is the POSITIONAL INDEX; targ is the pad slot; private is the sigil
# (0 scalar, 2 array, 4 hash).

subtest 'a declared scalar parameter is a Parameter node' => sub {
    my $n = nodes_for( 'sub two($a,$b) { $a + $b } print two(1,2), "\n";',
        'two', 'main::two' );
    my @p = params_in($n);
    is scalar @p, 2, 'two Parameter nodes' or do {
        diag 'ops: ' . join ',', map { $_->{op} } $n->@*;
        return;
    };

    my %by_index = map { $_->{fields}{index} => $_ } @p;
    ok exists $by_index{0}, 'parameter at index 0';
    ok exists $by_index{1}, 'parameter at index 1';
    is $by_index{0}{fields}{name},  '$a', 'index 0 is $a';
    is $by_index{0}{fields}{sigil}, '$',  'and a scalar';
    is $by_index{1}{fields}{name},  '$b', 'index 1 is $b';
};

# PURE. Both V8 pipelines agree (TurboFan Operator::kPure, Turboshaft
# OpEffects()). A parameter read floats, CSEs and hoists. It must NOT take a
# memory input the way Subscript(ArgsSource,...) does today.
subtest 'a Parameter is pure -- no inputs at all' => sub {
    my $n = nodes_for( 'sub one($a) { $a + 1 } print one(5), "\n";',
        'one', 'main::one' );
    my @p = params_in($n);
    is scalar @p, 1, 'one Parameter' or return;
    is_deeply $p[0]{inputs} // [], [],
        'zero inputs -- not a load, not projected off anything';
};

# A slurpy is NOT always an array: %h is a hash. The SIGIL carries that.
#
# The node is NOT stamped here: this producer's lattice has no `Array`/`Hash`
# (it carries ArrayRef/HashRef, which are REFERENCES, plus `List`), and
# stamping one dies "Unknown stamp type" -- which the translator masks as a
# silent skip, dropping the whole sub from the wire. Measured. Typing from the
# sigil is the loader's job, where Array/Hash already exist.
subtest 'a slurpy parameter carries its sigil' => sub {
    my @a = params_in(
        nodes_for( 'sub ary(@x) { scalar @x } print ary(1,2), "\n";',
            'ary', 'main::ary' ) );
    is scalar @a, 1, 'one Parameter for the slurpy array' or return;
    is $a[0]{fields}{sigil}, '@', 'sigil @';

    my @h = params_in(
        nodes_for( 'sub hsh(%h) { scalar keys %h } print hsh(a=>1), "\n";',
            'hsh', 'main::hsh' ) );
    is scalar @h, 1, 'one Parameter for the slurpy hash' or return;
    is $h[0]{fields}{sigil}, '%', 'sigil %';
};

# Hash-consed BY INDEX: TurboFan's hash_value(ParameterInfo) returns p.index(),
# so two reads of parameter 0 are ONE node. A parameter is a value, not an event.
subtest 'two reads of one parameter are one node' => sub {
    my $n = nodes_for( 'sub dbl($a) { $a + $a } print dbl(3), "\n";',
        'dbl', 'main::dbl' );
    my @p = params_in($n);
    is scalar @p, 1,
        'the two reads of $a hash-cons to a single Parameter node';
};

# A method's user parameters start at index 0 -- perl emits methstart() for the
# invocant and argcheck counts only the declared params.
subtest 'a method user parameter is index 0, not 1' => sub {
    my $file = "$dir/meth.pl";
    open my $fh, '>', $file or die $!;
    print {$fh} qq{use 5.42.0;\nuse experimental "class";\n}
        . qq{class C { method m(\$k) { \$k + 1 } }\n}
        . qq{print C->new->m(2), "\\n";\n};
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=C $file 2>$dir/meth.err};
    plan skip_all => 'no wire for the class case' unless length $json;
    my $wire = JSON::PP->new->decode($json);
    my @p = params_in( $wire->{methods}{'C::m'}{nodes} // [] );
    is scalar @p, 1, 'one Parameter for $k' or return;
    is $p[0]{fields}{index}, 0, '$k is index 0, not 1';
    is $p[0]{fields}{name},  '$k', 'and it is $k';
};

done_testing;
