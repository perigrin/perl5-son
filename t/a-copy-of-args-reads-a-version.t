# ABOUTME: A callee's copy of @_ (`my ($p) = @_`, `my @l = @_`, `my ($p, @r) = @_`) reads @_ where it
# ABOUTME: stands, at a version: never bound to @_ itself, never a record over ArgsSource (audit 2, K1).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE DEFECT (second final audit, class K1): `sub f { my ($p) = @_; $_[0] = 9;
# $p } f($x)` printed 9 for perl's 1. The copy was a record over ArgsSource
# with no version (chalk made it at $p's first use, after the store), and
# `my @l = @_` was bound to ArgsSource itself, so @l was @_.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null);
    return JSON::PP->new->decode($json);
}

my @k1 = (
    'my $x=1; sub f { my ($p)=@_; $_[0]=9; $p } print f($x), "\n";',
    'my @a=(1,2); sub f { my ($p,$q)=@_; $_[0]=9; "$p$q" } print f(@a),"@a\n";',
    'my @a=(1,2); sub f { my @l=@_; $_[0]=9; "@l" } print f(@a), "\n";',
    'my @a=(1,2); sub f { my @l=@_; @a=(); "@l" } print f(@a), "\n";',
    'my @a=(1,2); sub f { my ($p,@r)=@_; $a[1]=9; "$p@r" } print f(@a), "\n";',
    'my @a=(1,2); sub f { my $n=@_; my @l=@_; $_[1]=9; "$n@l" } print f(@a), "\n";',
    'my @a=(1,2); sub f { my @l=(0,@_); $a[0]=9; "@l" } print f(@a), "\n";',
    'package C; sub new { bless {v=>1}, shift } sub m { my ($s,@l)=@_; $_[1]=9; "@l" } package main; my @a=(1,2); print C->new->m(@a), "@a\n";',
);

for my $src (@k1) {
    my $w = wire($src);
    my @v = SoN::Verify::verify($w)->{violations}->@*;
    is [ map { "$_->{op}#$_->{node} $_->{rule}" } @v ], [], "verifies clean: $src";
    for my $g ( grep { !/__PROGRAM__/ } sort keys $w->{methods}->%* ) {
        my @nodes = $w->{methods}{$g}{nodes}->@*;
        my %by = map { $_->{id} => $_ } @nodes;
        my %args = map { $_->{id} => 1 } grep { $_->{op} eq 'ArgsSource' } @nodes;
        # (a record over @_: its targets take @_ whenever they are first read)
        my @rec = grep { $_->{op} eq 'Assign' && ( $_->{fields} // {} )->{record} && grep { defined && !ref && $args{$_} } $_->{inputs}->@* } @nodes;
        is scalar(@rec), 0, "$g: no record over \@_";
        # (@_ itself read as a value by what joins or returns it: `my @l = @_` bound to @_)
        my @bound = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'join' && grep { defined && !ref && $args{$_} } $_->{inputs}->@* } @nodes;
        is scalar(@bound), 0, "$g: \"\@l\" is not \"\@_\"";
    }
}

# THE VERIFIER SEES THE OLD SHAPE: a record over @_ whose target is read is a
# read of @_ with no version.
{   my $w = wire('my $x=1; sub f { my $p; ($p) = @_; $p } print f($x), "\n";');
    my $nodes = $w->{methods}{'main::f'}{nodes};
    my ($args) = grep { $_->{op} eq 'ArgsSource' } @$nodes;
    my ($pad)  = grep { $_->{op} eq 'PadAccess' && ( $_->{fields}{symbol} // '' ) eq 'p' } @$nodes;
    ok $args && $pad, 'the hand-made wire has @_ and $p';
    my $id = 1 + ( sort { $b <=> $a } map { $_->{id} } @$nodes )[0];
    # (the record the producer made before audit 2: [$p, @_], read by the Return through $p)
    @$nodes = grep { !( $_->{op} eq 'Assign' && ( $_->{fields}{targets} // 0 ) ) } @$nodes;
    push @$nodes, { id => $id, op => 'Assign', inputs => [ $pad->{id}, $args->{id} ], fields => { record => JSON::PP::true, targets => 1 }, stamp => 'List' };
    my ($ret) = grep { $_->{op} eq 'Return' } @$nodes;
    $ret->{inputs} = [ $pad->{id} ];
    my @v = SoN::Verify::verify($w)->{violations}->@*;
    ok( ( grep { $_->{rule} eq 'read-unversioned:args' } @v ), 'a read record over @_ is rejected' )
        or diag join '; ', map { "$_->{op}#$_->{node} $_->{rule}" } @v;
}

done_testing;
