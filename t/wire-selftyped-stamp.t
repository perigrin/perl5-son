# ABOUTME: Nodes whose type is fixed by the operation or by their own attrs.
# ABOUTME: Each answer here was already in the producer's hand at construction.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub stamp_of ($src, $name, $op) {
    my $wire = wire_for($src, $name);
    my ($n) = grep { $_->{op} eq $op }
              ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    return $n && $n->{stamp};
}

# `!$x` yields a boolean whatever $x is. Fixed by the OPERATION, needing no
# inference at all -- the same category as Defined and RegexMatch, which the
# factory's %SELF_TYPED_OPS already covers. Not was simply missing from it.
subtest 'logical negation is Boolean' => sub {
    is stamp_of('my $a = 3; my $x = $a // return 99; say($x + 1);', 'not', 'Not'),
        'Boolean', '! yields Boolean';
};

# `\@a` is a reference to an array: ArrayRef. Fixed by the operand's kind, which
# the producer is holding -- the operand node is right there as the input.
subtest 'a reference takes its operand kind' => sub {
    is stamp_of('my @a = (1, 2, 3); my $r = \@a; $r->[0] = 42; say($a[0]);',
                'ref_arr', 'Ref'),
        'ArrayRef', '\\@array is an ArrayRef';
};

# A compiled regex is a Regex. The producer wrote const_type => 'regex' into
# this node's OWN attributes and then stamped it Unknown.
subtest 'a qr// constant is a Regex' => sub {
    my $wire = wire_for('my $re = qr/foo/; my $s = "foobar"; say($s =~ $re ? 1 : 0);',
                        'qr');
    my ($re) = grep {
        $_->{op} eq 'Constant' && ($_->{fields}{const_type} // '') eq 'regex'
    } ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    ok defined $re, 'the regex constant exists' or return;
    is $re->{stamp}, 'Regex', 'qr// carries its declared const_type as its stamp';
};

# BILATERAL for the constant case: a non-regex constant must NOT become Regex.
subtest 'a plain constant is unaffected' => sub {
    my $wire = wire_for('my $n = 42; say($n);', 'plainconst');
    my @c = grep { $_->{op} eq 'Constant' && ($_->{fields}{const_type} // '') eq 'integer' }
            ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    ok @c >= 1, 'an integer constant exists' or return;
    is $c[0]{stamp}, 'Int', 'an integer constant is still Int';
};

# Arithmetic over typed operands is decidable: Int * Int is Int. The operands
# were stamped; the result was not.
subtest 'arithmetic over typed operands is typed' => sub {
    my $src = 'use feature "class"; no warnings "experimental::class";
class Box { field $val :param = 0; method double { return $val * 2 } }
my $b = Box->new(val => 3); say($b->double);';
    my $file = "$dir/arith.pl";
    open my $fh, '>', $file or die; print {$fh} "use 5.42.0;\n$src\n"; close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/arith.err};
    my $wire = JSON::PP->new->decode($json);
    my ($m) = grep { $_->{op} eq 'Multiply' }
              ($wire->{methods}{'Box::double'}{nodes} // [])->@*;
    ok defined $m, 'the Multiply node exists' or return;
    is $m->{stamp}, 'Int', 'Int * Int is Int';
};

# THE GUARD, UPDATED. This subtest asserted that `$n * 2` stays Unknown when $n
# comes from `shift` -- true when nothing propagated BACKWARD, and false now.
#
# `*` is numeric in Perl, so it CONSTRAINS its operands whatever they held:
# f("7") returns 14, the string numified before the multiply. Every value that
# reaches the operand and survives to the product is a number, by construction
# of the operator. That is ordinary type inference -- HM emits T($n) == Num from
# the same expression and solves it; abstract interpretation narrows from the
# use site. The producer stating it is not a guess about callers.
#
# `Num` and not `Int`: f(1.5) is legal and returns 3.
#
# What the guard now checks is the thing that IS still unknowable: the ARGUMENT
# type. `shift` off @_ is the Array[Scalar] wall, and no operator constrains it.
subtest 'arithmetic over an untyped operand takes the operator constraint' => sub {
    my $wire = wire_for('sub f { my $n = shift; return $n * 2 } print f(3), "\n";',
                        'arith_unknown');
    my ($m) = grep { $_->{op} eq 'Multiply' }
              ($wire->{methods}{'main::f'}{nodes} // [])->@*;
    ok defined $m, 'the Multiply node exists' or return;
    is $m->{stamp}, 'Num', '`* 2` makes the product Num, whatever shift returned';
    isnt $m->{stamp}, 'Int', 'and NOT Int -- f(1.5) is legal';
};

done_testing;
