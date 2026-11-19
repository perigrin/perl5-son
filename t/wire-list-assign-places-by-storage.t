# ABOUTME: A list assignment is put on the memory chain by where each target LIVES
# ABOUTME: (element, slice, cell, aggregate, package), never by a target's stamp.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE DEFECT (audit 2026-11-19, W2; docs/plans/2026-11-19-sigil-stamp-investigation.md).
# The aassign fallback pinned its Assign by a list of node kinds -- in a loop,
# an address-taken `my`, a PostfixDeref, a FieldAccess -- and asked "is a
# target an aggregate?" of its STAMP. A target the list missed was a store
# with no control_in and no consumer: gone. 15 probes printed a wrong answer.
#
# THE RULE NOW: each target has a storage class read from the node that names
# it (the pad entry's sigil, the node kind), and the Assign is placed -- by
# _place, as every store is -- unless every target is an SSA `my` scalar bound
# by position. That one case is a record of a rebinding, not a store.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return length $json ? JSON::PP->new->utf8->decode($json) : undef;
}

sub nodes ( $w, $g = 'main::__PROGRAM__' ) { ( $w->{methods}{$g}{nodes} // [] )->@* }

# The list Assign of a graph: the one with a `targets` field, or the only one
# that is not a single-target scalar store.
sub list_assign ( $w, $g = 'main::__PROGRAM__' ) {
    my @a = grep { $_->{op} eq 'Assign' && defined $_->{fields}{targets} } nodes( $w, $g );
    return $a[-1];
}

sub floating ($w) {
    [ map { "$_->{rule} $_->{op}#$_->{node} $_->{detail}" }
      grep { $_->{rule} =~ /\A(?:write-floating|effect-rides-value)\z/ && $_->{op} eq 'Assign' }
      SoN::Verify::verify($w)->{violations}->@* ];
}

my @stored = (
    [ 'array elements'        => 'my @a = (1,2); ($a[0], $a[1]) = ($a[1], $a[0]); print "@a\n";' ],
    [ 'hash elements'         => 'my %h = (a=>1, b=>2); ($h{a}, $h{b}) = ($h{b}, $h{a}); print "$h{a} $h{b}\n";' ],
    [ 'a hash slice'          => 'my %h; @h{qw(a b)} = (1,2); print "$h{a} $h{b}\n";' ],
    [ 'an array slice'        => 'my @a = (0,0,0); @a[0,1] = (5,6); print "@a\n";' ],
    [ 'elements through a ref' => 'my $r = [0,0]; ($r->[0], $r->[1]) = (3,4); print "@$r\n";' ],
    [ 'package array elements' => 'our @g = (0,0); ($g[0], $g[1]) = (3,4); print "@g\n";' ],
    [ 'a captured scalar'     => 'my $x = 1; my $g = sub { $x }; ($x) = (7); print $g->(), "\n";' ],
    [ 'an element and a scalar' => 'my @a = (0); my $c; ($a[0], $c) = (5,6); print "$a[0] $c\n";' ],
    [ 'a scalar and a `my` array' => 'my ($f, @rest) = (1,2,3); print "$f|@rest\n";' ],
    [ 'a scalar and a `my` hash'  => 'my ($k, %h) = ("x", a => 1); print "$k $h{a}\n";' ],
);
for my $c (@stored) {
    my ( $name, $src ) = @$c;
    subtest "$name: the Assign is on the chain" => sub {
        my $w = wire($src) or return fail "no wire for: $src";
        my $a = list_assign($w) or return fail 'no list Assign';
        ok defined $a->{control_in}, 'it has a control_in';
        is floating($w), [], 'the verifier sees no floating Assign';
    };
}

subtest '@_ = LIST in a sub is a store' => sub {
    my $w = wire('sub f { @_ = (9, 9); $_[0] = 3 } my $x = 1; f($x); print "$x\n";');
    my $a = list_assign( $w, 'main::f' ) or return fail 'no list Assign';
    ok defined $a->{control_in}, 'it has a control_in';
    is floating($w), [], 'the verifier sees no floating Assign';
};

subtest 'a read after the store names it as its memory version' => sub {
    my $w  = wire('my @a = (1,2); ($a[0], $a[1]) = ($a[1], $a[0]); print "@a\n";');
    my $a  = list_assign($w);
    my %by = map { $_->{id} => $_ } nodes($w);
    my ($join) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'join' } nodes($w);
    ok $join, 'the print joins @a' or return;
    my @elems = grep { $_->{op} eq 'Subscript' } map { $by{$_} } grep { defined && !ref } $join->{inputs}->@*;
    # Either the join reads the container at the Assign's version, or each
    # element read does.
    my @versions = ( $join->{fields}{memory_input} ? $join->{inputs}[-1] : () ), map { $_->{inputs}[2] } @elems;
    ok scalar( grep { defined && $_ == $a->{id} } @versions ), 'a later read is at the Assign'
        or diag "versions: @versions, Assign: $a->{id}";
};

# BY THE SIGIL, NOT THE STAMP. A bare `my @rest` PadAccess is unstamped (or
# stamped by whatever used it), so the stamp test took it for a scalar and
# bound targets to values by position.
subtest 'an aggregate target has no position: the scalar after it is not bound to a value' => sub {
    my $w  = wire('my (@rest, $f) = (1,2,3); print defined $f ? "def" : "undef", "|@rest\n";');
    my %by = map { $_->{id} => $_ } nodes($w);
    my ($def) = grep { $_->{op} eq 'Defined' } nodes($w);
    ok $def, 'defined $f is tested' or return;
    my $operand = $by{ $def->{inputs}[0] };
    isnt $operand->{op}, 'Constant', '$f is not the constant 2';
};

subtest 'a scalar from an array is a copy of the element, not the array' => sub {
    my $w  = wire('my @r; push @r, 2, 3; my ($f) = @r; pop @r; pop @r; print "$f\n";');
    my %by = map { $_->{id} => $_ } nodes($w);
    my ($print) = grep { $_->{op} eq 'Print' } nodes($w);
    my @cone = ($print);
    my %seen;
    while ( my $x = shift @cone ) {
        next if $seen{ $x->{id} }++;
        push @cone, map { $by{$_} } grep { defined && !ref } ( $x->{inputs} // [] )->@*;
    }
    # $f is element 0 of @r read at the version the assignment stands at
    # (after the push, before the pops): a copy. It was the array itself.
    my ($push) = grep { $_->{op} eq 'Call' && $_->{fields}{name} eq 'push' } nodes($w);
    my @elem = grep { $_->{op} eq 'Subscript' } map { $by{$_} } keys %seen;
    is scalar(@elem), 1, 'the print reads one element' or return;
    is $by{ $elem[0]{inputs}[0] }{fields}{symbol}, 'r', 'of @r';
    is $elem[0]{inputs}[2], $push->{id}, 'at the memory version after the push';
    my @whole = grep { $_->{op} eq 'Coerce' && $by{ $_->{inputs}[0] }{op} eq 'PadAccess' } map { $by{$_} } keys %seen;
    is scalar(@whole), 0, 'and never the array as a value';
};

subtest 'SSA scalars bound by position stay a record' => sub {
    my $w = wire('my ($p, $q) = (1,2); print "$p $q\n";');
    my $a = list_assign($w) or return fail 'no list Assign';
    ok !defined $a->{control_in}, 'no control_in: nothing is stored';
    is SoN::Verify::verify($w)->{allowed}{record}, 1, 'the verifier counts it a record';
};

done_testing;
