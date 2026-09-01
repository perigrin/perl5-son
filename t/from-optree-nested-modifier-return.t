# ABOUTME: `return X if C` nested inside an if/else arm -- an exit two deep.
# ABOUTME: Same threading as the arm case, one construct further in.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub run_and_translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $out  = qx{$PERL $file 2>/dev/null};
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w, $g ) { return [ ( $w->{methods}{$g}{nodes} // [] )->@* ] }

# THE DEFECT, and the third instance of one pattern. An exiting construct hands
# _walk_branch a LOCAL exit accumulator, so the exit is detected and dropped,
# and refusing is the only honest option left. Fixed already for the if/else arm
# (2db8ba5); this is the statement modifier NESTED INSIDE such an arm, which
# passed `\my @mod_exits` for the same reason.
#
#     return 1 if $x;                         <- always worked
#     if (C) { return 1 } else { return 0 }   <- fixed in 2db8ba5
#     if (C) { return 9 if D; return 1 }      <- this
subtest 'a modifier return inside an if arm merges into the single exit' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { my $n = shift; if ($n > 0) { return 9 if $n > 3; return 1 } return 0 }
print f(5), f(1), f(-1);', 'nested-mod' );
    is $out, '910', 'perl says 910' or return;
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/function exit inside a statement modifier/,
        'no nested-modifier GAP';
};

# THREE EXITS, ONE Return. The two nested exits and the fall-through all reach
# one Return -- dropping any of them would still build a graph, with the wrong
# value on that path.
subtest 'all three exits reach a single Return' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'sub f { my $n = shift; if ($n > 0) { return 9 if $n > 3; return 1 } return 0 }
print f(5);', 'three-exits' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes( $w, 'main::f' );
    ok scalar($ns->@*), 'the sub has a graph' or return;

    my @ret = grep { ( $_->{op} // '' ) eq 'Return' } $ns->@*;
    is scalar(@ret), 1, 'exactly one Return' or return;

    my %by = map { $_->{id} => $_ } $ns->@*;
    my $val = $by{ ( $ret[0]{inputs} // [] )->[0] // -1 };
    is( ( $val->{op} // '' ), 'Phi',
        'its value is a Phi over every exiting path' );
};

# THE OUTER FORMS STILL WORK -- a fix that rewired the accumulator must not
# disturb the two shapes that already lowered.
subtest 'the simpler exit forms are unchanged' => sub {
    my ( $out1, $w1, $e1 ) = run_and_translate(
        'sub f { my $x = shift; return 1 if $x; return 0 } print f(1), f(0);',
        'plain-mod' );
    is $out1, '10', 'plain modifier: perl says 10';
    ok $w1, 'and it translates' or diag($e1);

    my ( $out2, $w2, $e2 ) = run_and_translate(
        'sub f { my $x = shift; if ($x) { return 1 } else { return 0 } }
print f(1), f(0);', 'plain-arm' );
    is $out2, '10', 'if/else arms: perl says 10';
    ok $w2, 'and it translates' or diag($e2);
};

done_testing;
