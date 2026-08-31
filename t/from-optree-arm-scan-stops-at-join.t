# ABOUTME: An arm scan must stop at the ternary's JOIN, not run into the next
# ABOUTME: statement -- a store after the ternary is not a store INSIDE an arm.
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
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

# THE DEFECT. Two statements, and the ternary's arms are plain constants:
#
#     print "$h{k}" eq "v" ? "y\n" : "n\n";
#     $h{k} = "v";
#
# was refused as "a value-context ternary with a branch-guarded element store".
# There is no store in either arm. The scan walks ->next from an arm start to a
# $stop, and $stop was THE OTHER ARM -- which the false arm never reaches, so
# the walk ran off the end of the ternary, through the join, and into the next
# statement, where it found the store and blamed the arm.
#
# Measured exec order (B::Concise) for the reproducer:
#     8  cond_expr(other->9)
#     9  const "y\n"      <- true arm, then goto a
#     g  const "n\n"      <- false arm; ->next is a
#     a  print            <- THE JOIN
#     b  nextstate        <- the next statement begins
#     d  multideref($h{"k"}) sKM*   <- the store the scan wrongly attributed
#
# The bound is the JOIN, which the handler already computes as $join_addr and
# already passes to _arm_has_void_call and _arm_has_die. The two older
# detectors were simply never given it.
subtest 'a store after the ternary is not a store in its arm' => sub {
    my ( $wire, $err ) = translate(
        qq{print "\$h{k}" eq "v" ? "y\\n" : "n\\n";\n\$h{k} = "v";},
        'store-after' );
    unlike $err, qr/branch-guarded element store/,
        'it is not refused as a branch-guarded element store';
    ok $wire, 'and the program translates';
};

# THE REFUSAL MUST SURVIVE where the store really IS in an arm. Without this the
# fix could be "delete the detector", which passes the case above for the wrong
# reason.
subtest 'a store genuinely inside a consumed arm still refuses' => sub {
    my ( undef, $err ) = translate(
        q{our @a = (1,2); my $c = 1; my $x = $c ? ($a[0] = 7) : ($a[1] = 8); print $x;},
        'store-inside' );
    like $err, qr/GAP:/, 'a real branch-guarded element store still refuses';
};

# AND THE VOID FORM still lowers, as it did before -- it was never the refused
# shape, and a bound fix must not change it.
subtest 'a void if/else with element stores still lowers' => sub {
    my ( $wire, $err ) = translate(
        q{our @a = (1,2); my $c = 1; if ($c) { $a[0] = 7 } else { $a[1] = 8 } print $a[0];},
        'void-store' );
    ok $wire, 'the void form translates' or diag($err);
};

done_testing;
