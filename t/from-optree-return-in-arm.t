# ABOUTME: `if (C) { return X } else { return Y }` -- an exit in an if/else arm.
# ABOUTME: The statement-modifier form already threads this; the arm form did not.
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

# THE DEFECT. An explicit `return` inside an if/else ARM was refused, while the
# same exit written as a statement MODIFIER already worked:
#
#     return 1 if $x; return 0;                    <- lowered
#     if ($x) { return 1 } else { return 0 }       <- GAP
#
# The machinery was all present. _walk_branch records an exit's control edge
# into whatever accumulator it is handed, and the modifier path hands it the
# function-wide @exits so _build_single_exit can assemble the Phi. The arm path
# handed it a LOCAL @arm_exits, detected the exit, and threw it away -- so the
# exit was seen and then dropped, and the only honest thing left was to refuse.
subtest 'both arms returning lowers' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { my $x = shift; if ($x) { return 1 } else { return 0 } }
print f(1), f(0);', 'both-return' );
    is $out, '10', 'perl says 10' or return;
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/function exit inside an if\/else arm/, 'no arm-exit GAP';
};

# ONE ARM EXITING is the asymmetric case: the other arm falls through to the
# code after the if/else, so the function has two exits reaching one Return.
subtest 'one arm returning, the other falling through' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { my $x = shift; if ($x) { return 1 } return 2 }
print f(1), f(0);', 'one-return' );
    is $out, '12', 'perl says 12' or return;
    ok $w, 'it translates' or diag($err), return;
    unlike $err, qr/function exit inside an if\/else arm/, 'no arm-exit GAP';
};

# THE EXITS MUST MERGE INTO ONE Return. Dropping an exit would still produce a
# graph -- with the wrong value on one path -- so assert the single-exit shape.
subtest 'the arm exits reach a single Return' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'sub f { my $x = shift; if ($x) { return 1 } else { return 0 } }
print f(1);', 'single-exit' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes( $w, 'main::f' );
    ok scalar($ns->@*), 'the sub has a graph' or return;

    my @ret = grep { ( $_->{op} // '' ) eq 'Return' } $ns->@*;
    is scalar(@ret), 1, 'exactly one Return -- the exits merged' or return;

    my %by = map { $_->{id} => $_ } $ns->@*;
    my $val = $by{ ( $ret[0]{inputs} // [] )->[0] // -1 };
    is( ( $val->{op} // '' ), 'Phi',
        'and its value is a Phi over the two arms, not one arm alone' );
};

# THE MODIFIER FORM IS UNCHANGED -- it is the path that already worked, and a
# fix that rewired the shared accumulator must not disturb it.
subtest 'a statement-modifier return still lowers' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { my $x = shift; return 1 if $x; return 0 }
print f(1), f(0);', 'modifier' );
    is $out, '10', 'perl says 10';
    ok $w, 'it translates' or diag($err);
};

done_testing;
