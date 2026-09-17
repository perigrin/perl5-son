# ABOUTME: a widened loop Phi restamps its consumers instead of refusing them.
# ABOUTME: the old predicate compared a consumer's RESULT to its operand's join.
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

sub phis_of ( $wire ) {
    return [ grep { ( $_->{op} // '' ) eq 'Phi' }
             ( ( $wire->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@* ) ];
}

# THE DEFECT. `_patch_loop_phi` already widens a loop Phi to join(init, back).
# `_stale_consumers` then refused the graph if any transitive consumer was
# stamped below that join -- comparing a consumer's RESULT against its
# OPERAND's type.
#
# A comparison is the case that exposes it. `NumLt` yields Boolean for ANY
# operands, so widening what it reads cannot change it -- yet
# join(Boolean, Num) is Scalar, because Boolean is a sibling of Str under
# Scalar and not comparable to Num at all. Measured across the suite with the
# masking removed, ALL 43 flagged nodes were comparisons:
#
#     NumLt/Boolean 16, NumGt/Boolean 14, NumEq/Boolean 7,
#     NumNe/Boolean 5, NumGe/Boolean 1
#
# not one of which can be stale by construction.
subtest 'a loop that widens its accumulator translates' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'widen-acc' );
my $t = 0; my $i = 0;
while ($i < 3) { my $u = $t + 1; $t += 0.5; $i++ }
print "$t\n";
SRC
    ok $wire, 'it translates rather than refusing' or diag($err), return;

    my %stamp = map { $_->{id} => ( $_->{stamp} // '' ) } phis_of($wire)->@*;
    my @s = sort values %stamp;
    ok( ( grep { $_ eq 'Num' } @s ),
        'the widened accumulator carries Num' );
    ok( ( grep { $_ eq 'Int' } @s ),
        'and the counter is STILL Int -- only what widens widens' );
};

# TWO PHIS FEEDING EACH OTHER is the sibling-cycle case: $x reads $y's Phi,
# which the back edge widens. One round is not enough, so this is what bounds
# the worklist.
subtest 'two Phis feeding each other both settle' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'widen-swap' );
my $x = 0; my $y = 0; my $t = 0; my $i = 0;
while ($i < 3) { $x = $y; $y = $t + 0.5; $i++ }
print "$x $y\n";
SRC
    ok $wire, 'it translates rather than refusing' or diag($err), return;
    ok scalar( phis_of($wire)->@* ) >= 2, 'the loop keeps its Phis';
};

# THE COUNTER-ONLY LOOP IS UNCHANGED. Nothing widens, so nothing restamps and
# Int must survive -- this is the precision the flag exists for, and the one
# the suite pins elsewhere.
subtest 'a loop that widens nothing keeps its Int' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'no-widen' );
my $s = 0; my $i = 0;
while ($i < 3) { $s += 1; $i++ }
print "$s\n";
SRC
    ok $wire, 'it translates' or diag($err), return;
    my @s = map { $_->{stamp} // '' } phis_of($wire)->@*;
    ok( ( grep { $_ eq 'Int' } @s ), 'the accumulator stays Int' );
    ok( !( grep { $_ eq 'Num' } @s ), 'and nothing was widened gratuitously' );
};

done_testing;
