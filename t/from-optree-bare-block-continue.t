# ABOUTME: a bare block with a continue whose body has no next/last/redo is straight-line.
# ABOUTME: the loop-exit forms still refuse -- next runs the continue, last and redo skip it.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# A BARE BLOCK WITH A `continue` AND NO LOOP-EXIT IS STRAIGHT-LINE CODE.
# Measured -- the block runs once, the continue runs once, and the optree has
# NO BACK EDGE:
#
#     my $n=0; { $n=1 } continue { $n+=10 }      $n is 11
#     my $n=0; $n=1; $n+=10;                     $n is 11
#
#     6 enterloop(next->9 last->c redo->7)
#     7 const 1 / padsv_store $n         the block
#     9 padsv $n / const 10 / add        the continue, falls straight in
#     c leaveloop
#
# It was refused with the loop-exit forms because the guard keys on
# `redoop == enter`, which says BARE BLOCK and says nothing about whether a
# next/last/redo is present.
# NOT LOWERED, AND BLOCKED ON IDENTIFYING THE CONSTRUCT rather than on the
# lowering. A bare block with a continue and no loop-exit shares its enterloop
# shape with two forms that translate correctly today -- measured across every
# enterloop form:
#
#     bare+continue simple   next=padsv     redo=const      want to lower
#     while+continue         next=padsv     redo=pushmark   already works
#     C-style for            next=padsv     redo=pushmark   already works
#     bare+continue redo     next=pushmark  redo=enter      must refuse
#
# No local property separates the first from the middle two, and guessing one
# risks sending a working `while+continue` or C-style `for` down the
# straight-line path -- trading an honest refusal for a miscompile. TODO
# rather than attempted again without a discriminator.
#
# See docs/plans/2026-09-17-the-gap-census-audited.md for the full attempt.
{
    my $todo = todo 'no local property identifies a bare block with a continue';
    round_trips( <<'SRC', 'a continue with no loop-exit is sequential' );
my $n = 0;
{ $n = 1 } continue { $n += 10 }
print "$n\n";
SRC

    round_trips( <<'SRC', 'the continue sees the block\'s writes' );
my @o;
{ push @o, "b" } continue { push @o, "c" }
print join(",", @o), "\n";
SRC
}

# THE LOOP-EXIT FORMS STILL REFUSE, and they are a FACT rather than a missing
# lowering: the four exits have three different destinations, measured on
# 5.42.0.
#
#     fall off end   continue RUNS
#     next           continue RUNS
#     redo           continue SKIPPED (jumps to the block top)
#     last           continue SKIPPED (jumps past it)
#
#     { $i++; redo if $i<3 } continue { push @o,"c$i" }   ->  b1,b2,b3,c3
#     { next if $_ eq 4; return 20 } continue { return $_ }  ->  f(4) is 4
#     { last if $_ == 3; return 99 } continue { return 20 }  ->  f(3) is 3
#
# One region, three exit destinations. That is control flow the walker does
# not model, and refusing is correct until it does.
subtest 'a continue with redo still refuses' => sub {
    my ( $data, $err ) = graph_of(
        'my $i = 0; { $i++; redo if $i < 3 } continue { print "c\n" }' );
    like $err, qr/GAP:/, 'it is refused';
    like $err, qr/continue/, '... naming the construct';
};

subtest 'a continue with next still refuses' => sub {
    my ( $data, $err ) = graph_of(
        'for my $x (1,2) { { next if $x == 1 } continue { print "c\n" } }' );
    like $err, qr/GAP:/, 'it is refused';
};

done_testing;
