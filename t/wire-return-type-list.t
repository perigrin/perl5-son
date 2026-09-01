# ABOUTME: A sub that returns an aggregate declares List, not Array -- return
# ABOUTME: position imposes list context, so no sub ever returns a container.

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
    my $out  = qx{$PERL $file 2>/dev/null};
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub return_type_of ( $w, $sub ) {
    my $subs = ( $w->{classes}{main}{subs} // {} );
    return ( $subs->{$sub} // {} )->{return_type};
}

# `return @a` NEVER YIELDS A CONTAINER. Return position imposes list context on
# its operand, so the array flattens exactly as `(99,@x)` does. Measured:
#
#     sub agg { my @a=(10,20,30); return @a }
#     my @l = agg();   -> 3 elements
#     my $s = agg();   -> 3 (the count)
#     sub aref { return \@a }  my $r = aref();  -> an ARRAY ref
#
# A container survives a return ONLY through a reference, which is a genuine
# scalar. So the declared type is List for every aggregate return; declaring
# Array reports the OPERAND's type where the RETURN's belongs, and sends a
# consumer looking for a container that is never produced.

subtest 'an aggregate return declares List, not Array' => sub {
    my ( $out, $w, $err ) = translate(
        'sub agg { my @a=(10,20,30); return @a } my @l = agg(); print scalar(@l);',
        'agg-type' );
    is $out, '3', 'perl flattens it to three values' or return;
    ok $w, 'it translates' or do { diag($err); return };

    is return_type_of( $w, 'agg' ), 'List',
        'the declared return type is List';
};

subtest 'a literal list return also declares List' => sub {
    my ( undef, $w, $err ) = translate(
        'sub lit { return (10,20,30) } my @l = lit(); print scalar(@l);',
        'lit-type' );
    ok $w, 'it translates' or do { diag($err); return };
    is return_type_of( $w, 'lit' ), 'List', 'List';
};

# A REFERENCE RETURN IS A SCALAR and must NOT become List -- that is the one
# shape where a container really does survive, as a ref.
subtest 'a reference return stays a reference type' => sub {
    my ( $out, $w, $err ) = translate(
        'sub aref { my @a=(1,2,3); return \@a } my $r = aref(); print scalar(@$r);',
        'aref-type' );
    is $out, '3', 'perl returns a usable ref' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my $t = return_type_of( $w, 'aref' ) // '';
    isnt $t, 'List', 'a ref return is not List';
    isnt $t, 'Array', '... and not Array either';
};

# A SCALAR RETURN IS UNAFFECTED. A fix that mapped every return to List would
# be a regression dressed as consistency.
subtest 'a scalar return is unchanged' => sub {
    my ( undef, $w, $err ) = translate(
        'sub one { return 42 } print one();', 'one-type' );
    ok $w, 'it translates' or do { diag($err); return };
    my $t = return_type_of( $w, 'one' ) // '';
    isnt $t, 'List', 'a scalar return is not List';
};

done_testing;
