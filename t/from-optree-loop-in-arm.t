# ABOUTME: A foreach inside an if/else arm translates like one outside it.
# ABOUTME: enteriter lived in the main walk loop, unreachable from _walk_branch.
use 5.42.0;
use utf8;
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
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# THE DEFECT. `enteriter` is dispatched in the MAIN walk loop rather than in
# _step, and _walk_branch only calls _step -- so a loop outside an arm
# translated while the identical loop inside one stopped dead at `enteriter`,
# surfacing as "untranslatable op inside an if/else arm".
#
# Measured both ways before the fix: the l1 form below translated, the l2 form
# refused. Same loop, same bounds, same body.
subtest 'a foreach in an else arm translates' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0;
if ($ARGV[0]) { $n = 1 } else { foreach my $i (1..3) { $n = $n + $i } }
print $n;', 'loop-in-else' );
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/untranslatable op inside an if\/else arm/,
        'no arm-stopped GAP';
};

subtest 'a foreach in a then arm translates' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0;
if ($ARGV[0]) { foreach my $i (1..3) { $n = $n + $i } } else { $n = 1 }
print $n;', 'loop-in-then' );
    ok $w, 'it translates' or diag($err), return;
    unlike $err, qr/untranslatable op inside an if\/else arm/, 'no arm GAP';
};

# THE LOOP MUST ACTUALLY BE BUILT, not merely stepped over: a walk that skipped
# enteriter without emitting anything would also stop GAPping while silently
# dropping the loop body.
subtest 'the arm loop emits real loop structure' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0;
if ($ARGV[0]) { $n = 1 } else { foreach my $i (1..3) { $n = $n + $i } }
print $n;', 'loop-built' );
    ok $w, 'it translates' or diag($err), return;

    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
    ok scalar( grep { $_ eq 'Phi'  } @ops ), 'and an induction Phi';
};

# UNCHANGED OUTSIDE AN ARM. The main-loop path must keep working -- this is the
# form that already translated, and a move that broke it would be a regression
# the arm tests above cannot see.
subtest 'a foreach outside any arm still translates' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0; foreach my $i (1..3) { $n = $n + $i } print $n;',
        'loop-plain' );
    ok $w, 'it translates' or diag($err), return;
    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
};

done_testing;
