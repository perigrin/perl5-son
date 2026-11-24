# ABOUTME: Design B1: where something may die under a live `local` and no eval of its graph is
# ABOUTME: open, its way out is an Exc, the restores, then an Unwind marked `rethrow` (no catch).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Verify;
use SoN::Wire;
use SoN::Deparse;

# docs/plans/2026-11-24-copy-and-local-unwind.md, design B1 (the plan's Q9
# "rethrow pad"). `sub f { local $g = 2; 1 / $_[0] } eval { f(0) }; print $g`:
# perl prints 1. The division in f has no eval of f's around it, so its die
# left by no way on the wire and the restore after it never ran (re-audit
# 2026-11-23, class B; refused by chalk's W6 until this design).

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err) );
}
sub graph ( $w, $name ) {
    my @n = $w->{methods}{$name}{nodes}->@*;
    return ( \@n, { map { $_->{id} => $_ } @n } );
}
sub f ( $x, $k ) { ( $x->{fields} // {} )->{$k} }
sub is_g ( $x, $sym ) { $x && $x->{op} eq 'EntryDef' && ( f( $x, 'symbol' ) // '' ) eq $sym }
# the nodes standing on $from's control chain, in order
sub chain ( $nodes, $from ) {
    my @c;
    while ( my ($s) = grep { ( $_->{control_in} // -1 ) == $from } @$nodes ) { push @c, $s; $from = $s->{id} }
    return @c;
}

my %cases = (
    'a division'   => [ q{our $g = 1; sub f { local $g = 2; 1 / $_[0] } eval { f(0) }; print "$g\n";}, 'Divide' ],
    'a call'       => [ q{our $g = 1; sub u { die "u\n" } sub f { local $g = 2; u(); 1 } eval { f() }; print "$g\n";}, 'Call' ],
    'a dereference' => [ q{our $g = 1; sub f { local $g = 2; my $r = shift; $$r } eval { f("x") }; print "$g\n";}, 'PostfixDeref' ],
);
for my $what ( sort keys %cases ) {
    my ( $src, $op ) = $cases{$what}->@*;
    my $w = wire($src);
    my ( $nodes, $by ) = graph( $w, 'main::f' );
    my ($t) = grep { $_->{op} eq $op && defined $_->{control_in} } @$nodes;
    ok $t, "$what: the thrower stands on the chain" or next;
    my ($exc) = grep { $_->{op} eq 'Exc' && $_->{inputs}[0] == $t->{id} } @$nodes;
    ok $exc, "$what: it has an Exc, outside any eval" or next;
    my @c = chain( $nodes, $exc->{id} );
    ok( ( grep { $_->{op} eq 'EntryWrite' && is_g( $by->{ $_->{inputs}[0] }, 'g' ) } @c ), "$what: the edge puts \$g back" );
    my $u = $c[-1];
    is $u->{op}, 'Unwind', "$what: the edge ends in an Unwind";
    ok f( $u, 'rethrow' ), "$what: ... marked rethrow";
    is $u->{inputs}, [ $exc->{id} ], "$what: ... of the exception in flight";
    is $u->{mem_in}, $c[-2]{id}, "$what: ... after the last restore";
    ok !defined f( $u, 'eval_id' ), "$what: ... in no eval";
    is [ map { "$_->{rule}: $_->{why}" } grep { $_->{graph} eq 'main::f' } SoN::Verify::verify($w)->{violations}->@* ], [], "$what: the graph verifies";
}

# NO EDGE where nothing is live to put back, nor for the sub's own die (its
# locals are put back before it: _pin_die), nor in an eval of the sub (the
# catch is its way out).
for my $src (
    q{our $g = 1; sub f { 1 / $_[0] } eval { f(0) }; print "$g\n";},
    q{our $g = 1; sub f { local $g = 2; die "x\n" } eval { f() }; print "$g\n";},
    q{our $g = 1; sub f { eval { local $g = 2; 1 / $_[0] }; 1 } f(0); print "$g\n";},
) {
    my ($nodes) = graph( wire($src), 'main::f' );
    ok !( grep { $_->{op} eq 'Unwind' && f( $_, 'rethrow' ) } @$nodes ), "no rethrow edge: $src";
}

# THE DEPARSER READS v1, which has no way out: as_v1 drops each rethrow edge
# (its Exc, its restores, its Unwind), as it drops an eval's, and the
# rendering prints what perl prints.
{
    my $src = q{our $g = 1; sub g { print "$g\n" } sub f { local $g = 2; g(); 7 } print f(), " $g\n";};
    my $w = wire($src);
    my $v1 = SoN::Wire::as_v1($w);
    my @left = grep { $_->{op} eq 'Exc' || $_->{op} eq 'Unwind' } $v1->{methods}{'main::f'}{nodes}->@*;
    is scalar @left, 0, 'as_v1 drops the rethrow edge';
    my $d = SoN::Deparse->new;
    my $text = $d->render($w);
    ok defined $text, 'it renders' or diag $d->gap;
    open my $o, '>', "$dir/r.pl" or die $!; print $o $text // ''; close $o;
    open my $p, '>', "$dir/s.pl" or die $!; print $p $src; close $p;
    is scalar qx($^X $dir/r.pl 2>&1), scalar qx($^X $dir/s.pl 2>&1), '... and prints what perl prints';
}

done_testing;
