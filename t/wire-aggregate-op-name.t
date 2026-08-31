# ABOUTME: The container constructor is named for what it BUILDS, not for a ref.
# ABOUTME: `my @a=(1,2)` is not a reference; the stamp says which one it is.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub wire ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    die "no JSON for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# THE DEFECT WAS THE NAME, not the model. One node class builds every list
# container, and its STAMP says what the result is -- Array for `my @a=(1,2)`,
# ArrayRef for `[1,2]`. The class was called `ArrayRef`, so the op name
# asserted "reference" for a case the stamp called a plain array:
#
#     my @a = (10,20,30)   op=ArrayRef  stamp=Array      <- name lies
#     my $r = [1,2]        op=ArrayRef  stamp=ArrayRef
#
# perigrin: "There is no ArrayRef here." A lexical array is not a reference.
#
# IT COST A REAL MISCOMPILE. chalk read the op name, assumed it agreed with the
# stamp, and boxed unconditionally -- 37 corpus cases emitted nothing. Its first
# fix was also wrong (unbox for Array too, on the theory the two were one
# container reached two ways), which broke five genuine-reference cases. A
# consumer reading only the op name gets it wrong silently, which is the
# property a name should not have.
subtest 'a lexical array is an ArrayLiteral stamped Array' => sub {
    my $w = wire( 'my @a = (10,20,30); print scalar(@a);', 'lex-array' );
    my ($n) = grep { ( $_->{stamp} // '' ) eq 'Array' } nodes($w)->@*;

    ok $n, 'the container node is stamped Array' or return;
    is $n->{op}, 'ArrayLiteral',
        'and named for what it builds, not for a reference';
};

subtest 'an anonymous ref is the same op, stamped ArrayRef' => sub {
    my $w = wire( 'my $r = [1,2]; print scalar(@$r);', 'anon-ref' );
    my ($n) = grep { ( $_->{stamp} // '' ) eq 'ArrayRef' } nodes($w)->@*;

    ok $n, 'the container node is stamped ArrayRef' or return;
    is $n->{op}, 'ArrayLiteral',
        'one constructor for both -- the stamp carries the distinction';
};

# THE HASH SIDE MOVES WITH IT. `%h` and `{...}` have the same split.
subtest 'the hash constructor is named the same way' => sub {
    my $w = wire( 'my $h = {a=>1}; print scalar(keys %$h);', 'anon-hash' );
    my ($n) = grep { ( $_->{op} // '' ) eq 'HashLiteral' } nodes($w)->@*;
    ok $n, 'a HashLiteral node exists';
    is( ( $n->{stamp} // '' ), 'HashRef', 'stamped HashRef for `{...}`' ) if $n;
};

# NO NODE STILL CALLS ITSELF A REF. The whole point is that the op name stops
# asserting something the stamp may contradict.
subtest 'no ArrayRef or HashRef op remains on the wire' => sub {
    my $w = wire( 'my @a = (1,2); my $r = [3,4]; my $h = {k=>5};
print scalar(@a), scalar(@$r), scalar(keys %$h);', 'mixed' );
    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    is scalar( grep { $_ eq 'ArrayRef' || $_ eq 'HashRef' } @ops ), 0,
        'the ref-named ops are gone';
    ok scalar( grep { $_ eq 'ArrayLiteral' } @ops ), 'ArrayLiteral is emitted';
};

done_testing;
