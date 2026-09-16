# ABOUTME: a fused store's destination can be a package scalar, not only a pad slot.
# ABOUTME: `$bar = <FH>` carries its target on the op; a PadAccess-only guard drops it.
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,not_package=SoN $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $wire ) {
    return [ map { ( $wire->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $wire->{methods} // {} )->%* ) ];
}

# THE DEFECT. `$bar = <FH>` compiles with the assignment NULLED and the
# destination carried on the readline op itself -- the same OPf_STACKED shape
# `my $s = <$fh>` takes, and for the same reason. Measured on 5.42.0:
#
#     gvsv[*bar]   s             the destination, pushed FIRST
#     gv[*FH]      s
#     readline[t3] sKS/1         OPf_STACKED
#
# The guard that claims that destination required a PadAccess, so a package
# scalar fell through it: the EntryDef was left on the stack and the read's
# value reached nothing. base/rs.t reads its whole file this way
# (`$bar = <FH>` eleven times) and every comparison against $bar then read an
# unassigned global -- 24 of its 41 tests printed `not ok` where perl prints
# `ok`.
subtest 'a package scalar destination is claimed and stored' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'pkg-dest' );
open(FH, "<", "/dev/null") or die;
$bar = <FH>;
print "[$bar]";
SRC
    ok $wire, 'it translates' or diag($err), return;

    my $n = nodes($wire);
    my ($read) = grep { ( $_->{op} // '' ) eq 'Call'
                     && ( $_->{fields}{name} // '' ) eq 'readline' } $n->@*;
    ok $read, 'the readline is in the graph' or return;

    my ($write) = grep { ( $_->{op} // '' ) eq 'EntryWrite' } $n->@*;
    ok $write, 'and the store into the package scalar is too' or return;

    is $write->{inputs}[1], $read->{id},
        'the value stored is what the readline produced';

    my %by = map { $_->{id} => $_ } $n->@*;
    my $target = $by{ $write->{inputs}[0] };
    is( ( $target->{fields}{symbol} // '' ), 'bar',
        'and the target is $main::bar' );
};

# THE LEXICAL FORM IS UNCHANGED: a pad slot is private to its sub, so the SSA
# rebind IS the semantics and no store belongs on the memory chain.
subtest 'a pad destination still takes the rebind alone' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'pad-dest' );
open(FH, "<", "/dev/null") or die;
my $bar = <FH>;
print "[$bar]";
SRC
    ok $wire, 'it translates' or diag($err), return;

    my @write = grep { ( $_->{op} // '' ) eq 'EntryWrite' } nodes($wire)->@*;
    is scalar(@write), 0, 'no EntryWrite -- the pad rebind carries it';
};

done_testing;
