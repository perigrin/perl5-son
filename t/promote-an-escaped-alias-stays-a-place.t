# ABOUTME: SoN::Promote leaves an argument a place where the proof cannot show it private: a `my`
# ABOUTME: a closure captures or a reference reaches, an element a reference reaches, a caller's @_.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';

# THE DEFECT (audit 4, X5): SoN::AliasProof::conflict took a captured `my`
# scalar for one no unseen code can name (a capture is no `Ref`), spelled a
# `my` source `my:` where src() builds `my|G|$x` (so a store through a
# reference never reached one), and ended its table "no conflict". Each
# program here printed the value its argument had before the call.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    return JSON::PP->new->decode($json);
}
# arg($w, $graph, $i) -> the node main::f's call in $graph is handed as input $i
sub arg ( $w, $g, $i ) {
    my @n = $w->{methods}{$g}{nodes}->@*;
    my ($c) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'main::f' } @n;
    my ($a) = grep { $_->{id} == $c->{inputs}[$i] } @n;
    return $a;
}

for my $case (
    [ 'a closure handed in stores the captured `my`', 'sub f { $_[1]->(); $_[0] } my $x = 1; print f($x, sub { $x = 5 }), "\n";' ],
    [ 'a closure made in a sub stores its captured `my`', 'sub f { my $o = $_[0]; $_[1]->(); "$o$_[0]" } sub w { my $x = 1; f($x, sub { $x = 5 }) } print w(), "\n";', 'main::w' ],
    [ 'a file-level reference to the `my` is stored through', 'my $x = 1; my $r = \$x; sub f { $$r = 5; $_[0] } print f($x), "\n";' ],
    [ 'a reference handed in is stored through', 'sub f { my ($p,$r) = @_; $$r = 5; "$p$_[0]" } my $x = 1; print f($x, \$x), "\n";' ],
    [ 'a reference held in an array is stored through', 'my $x = 1; my @r = (\$x); sub f { my $o = $_[0]; ${$_[1][0]} = 5; "$o$_[0]" } print f($x, \@r), "\n";' ],
    [ 'a reference held in a hash is stored through', 'my $x = 1; my %o = (r => \$x); sub f { my $o = $_[0]; ${$_[1]{r}} = 5; "$o$_[0]" } print f($x, \%o), "\n";' ],
    [ 'a reference copied into a callee\'s array is stored through', 'my $x = 1; my $r = \$x; sub f { my @q = ($r); ${$q[0]} = 5; $_[0] } print f($x), "\n";' ],
    [ 'a reference to a package element is stored through', 'our @a = (1); my $r = \$a[0]; sub f { $$r = 5; $_[0] } print f($a[0]), "\n";' ],
    [ 'a reference to a `my` element is stored through', 'my @a = (1); my $r = \$a[0]; sub f { $$r = 5; $_[0] } print f($a[0]), "\n";' ],
    [ 'the caller\'s own @_ element handed on, its variable stored by name', 'our $x = 1; sub f { $x = 2; $_[0] } sub h { f($_[0]) } print h($x), "\n";', 'main::h' ],
) {
    my ( $what, $src, $g ) = @$case;
    my $a = arg( wire($src), $g // 'main::__PROGRAM__', 0 );
    ok( $a && $a->{fields}{place} && !$a->{fields}{promoted}, "$what: the argument stays a place" );
}

# WHAT STAYS PROMOTED: a `my` no reference reaches and no closure captures,
# whatever the callee calls -- code the wire cannot see cannot name it.
for my $case (
    [ 'a callee that only reads @_', 'my $x = 1; sub f { $_[0] } print f($x), "\n";' ],
    [ 'a callee that calls a closure capturing another variable', 'my $x = 1; my $y = 0; my $c = sub { $y = 5 }; sub f { $c->(); $_[0] } print f($x), "\n";' ],
    # (a store through a hash or array reference is an element's: a named
    # scalar is no element -- the deparser's round trip of chalk's
    # _stamp_method_call_reprs lost this promotion and printed nothing)
    [ 'a callee that stores through a hash reference', 'my $x = 1; my %h; sub f { $_[1]{k} = 2; $_[0] } print f($x, \%h), "\n";' ],
    [ 'a callee that stores through an array reference', 'my $x = 1; my @a; sub f { $_[1][0] = 2; $_[0] } print f($x, \@a), "\n";' ],
) {
    my ( $what, $src ) = @$case;
    my $a = arg( wire($src), 'main::__PROGRAM__', 0 );
    ok( $a && $a->{fields}{promoted}, "$what: the argument is promoted" );
}
done_testing;
