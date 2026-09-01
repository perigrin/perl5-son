# ABOUTME: `undef $x` clears a scalar -- a rebind to Undef, like `$x = undef`.
# ABOUTME: `undef @a` EMPTIES an aggregate, which is not the same and still GAPs.
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

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# `undef EXPR` AND `EXPR = undef` ARE NOT ONE OPERATION, measured:
#
#     my @a=(1,2,3); undef @a;   -> scalar(@a) is 0   (emptied)
#     my @b=(1,2,3); @b = undef; -> scalar(@b) is 1   (one undef element)
#
# For a SCALAR they coincide -- both leave it undefined -- and that is the case
# this lowers. perl compiles `undef $x` to a single `undef[$x] vK/TARGMY` op
# carrying its own targ, so the target is named ON THE OP and nothing needs
# popping: it is exactly the rebind the handler already performed for the
# no-operand form. The refusal fired first only because `undef $x` also sets
# OPf_KIDS.
subtest 'undef on a lexical scalar clears it' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my $x = 5; undef $x; print defined($x) ? "d" : "u";', 'undef-scalar' );
    is $out, 'u', 'perl leaves it undefined' or return;
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/undef\(EXPR\)/, 'no undef(EXPR) GAP';
};

# THE REBIND MUST REACH THE READ. A translation that dropped it would still
# build a graph -- with the pre-undef value flowing to the later read.
subtest 'the read after undef sees Undef, not the old value' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'my $x = 5; undef $x; my $y = $x; print 1;', 'undef-rebind' );
    ok $w, 'it translates' or diag($err), return;

    my @const = grep { ( $_->{op} // '' ) eq 'Constant' } nodes($w)->@*;
    ok scalar( grep { ( $_->{stamp} // '' ) eq 'Undef' } @const ),
        'an Undef constant is in the graph';
    is scalar( grep { ( $_->{fields}{value} // '' ) eq '5' } @const ), 0,
        'and the pre-undef 5 does not survive as a live value';
};

# AN AGGREGATE IS A DIFFERENT OPERATION and still refuses. `undef @a` empties
# the container; modelling it as a rebind to Undef would give a one-element
# array, which is what `@a = undef` means and is a silent miscompile.
subtest 'undef on an aggregate still refuses' => sub {
    for my $src ( 'my @a = (1,2); undef @a; print scalar(@a);',
                  'my %h = (a=>1); undef %h; print scalar(keys %h);' ) {
        my ( undef, undef, $err ) = run_and_translate( $src, 'undef-agg' );
        like $err, qr/GAP:/, "refused: $src";
    }
};

# THE BARE VALUE IS UNCHANGED -- `my $a = undef` and a bare `undef` were always
# the Undef constant, and a fix to the operator form must not disturb them.
subtest 'the undef VALUE still lowers' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my $a = undef; print defined($a) ? "d" : "u";', 'undef-value' );
    is $out, 'u', 'perl says undefined';
    ok $w, 'it translates' or diag($err);
};

done_testing;
