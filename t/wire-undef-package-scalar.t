# ABOUTME: `undef $g` on a PACKAGE scalar rebinds that name to undef, the same
# ABOUTME: operation `undef $x` performs on a lexical -- not a container empty.

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
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub prog_nodes ( $w ) { return ( $w->{methods}{'main::__PROGRAM__'}{nodes} // [] ) }

# A SCALAR OPERAND REBINDS A NAME; ONLY AN AGGREGATE EMPTIES A CONTAINER.
# The lexical form already lowers -- the walker reads the pad slot off the kid
# and rebinds it. A package scalar is the SAME operation on a differently-named
# slot, and it was refused only because the kid is a gvsv/rv2sv rather than a
# padsv. Measured, perl agrees they are one operation:
#
#     my $x = 5;  undef $x;   -> $x is undef
#     undef $a;               -> $a is undef  (package scalar)
#
# The aggregate cases stay refused: `undef @a` empties the container, which is
# not `@a = undef` (that would be a ONE-ELEMENT array), and modelling it as a
# rebind would produce exactly that wrong shape.

subtest 'undef on a package scalar lowers' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'undef $a; print defined($a) ? "d" : "u";', 'undef-pkg-scalar' );
    is $out, 'u', 'perl leaves it undefined' or return;
    ok $w, 'it translates rather than GAPping' or do { diag($err); return };

    my $ns = prog_nodes($w);
    ok scalar( grep {
        ( $_->{op} // '' ) eq 'Constant'
            && ( $_->{fields}{const_type} // '' ) eq 'undef'
    } $ns->@* ), 'an undef Constant is bound';
};

# THE REBIND MUST BE VISIBLE TO A LATER READ, which is the whole point: a
# binding nothing reads is not a rebind. Asserting only that translation
# succeeds would pass on a graph that dropped the write entirely.
subtest 'a later read sees the rebound undef' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        '$a = 5; undef $a; print defined($a) ? "d" : "u";', 'undef-pkg-read' );
    is $out, 'u', 'perl reads it as undefined' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my $ns = prog_nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;

    # `defined($a)` must test the UNDEF, not the 5 that preceded it.
    #
    # IT TESTS IT THROUGH MEMORY, not by reading a forwarded Constant. A
    # package scalar that some sub assigns is read through the memory chain
    # (see _package_scalars_written in FromOptree.pm), so the assertion is
    # that the read's memory version is the undef store -- which is the same
    # fact one indirection out, and the only spelling that stays true when
    # the writer is in another sub.
    my ($defined) = grep { ( $_->{op} // '' ) eq 'Defined' } $ns->@*;
    ok $defined, 'the program tests definedness' or return;
    my $tested = $by{ ( $defined->{inputs} // [] )->[0] // '' };
    ok $tested, 'and it tests something' or return;

    my $undef_id = ( grep {
        ( $_->{op} // '' ) eq 'Constant'
            && ( $_->{fields}{const_type} // '' ) eq 'undef'
    } $ns->@* )[0]{id};

    if ( ( $tested->{op} // '' ) eq 'Constant' ) {
        is $tested->{fields}{const_type} // '', 'undef',
            'it tests the rebound undef, not the earlier value';
    }
    else {
        is $tested->{op}, 'EntryDef', 'it tests a read of the package scalar';
        my $mem = $by{ ( $tested->{inputs} // [] )->[0] // '' };
        ok $mem, 'and that read carries a memory version' or return;
        is $mem->{op}, 'EntryWrite', 'whose producer is a store' or return;
        is $mem->{inputs}[1], $undef_id,
            'and that store wrote the undef, not the earlier 5';
    }
};

# AGGREGATES NOW LOWER TOO, as an EMPTY container rather than a rebind to
# undef. `undef @a` and `@a = ()` are the same operation (0 elements); what
# neither is is `@a = undef`, which leaves ONE undef element -- pinned in
# t/wire-aggregate-clear.t so a future change cannot collapse them.
subtest 'undef on an aggregate empties it' => sub {
    for my $case ( [ 'my @z=(1,2); undef @z; print scalar(@z);', '0', 'array' ],
                   [ 'my %z=(a=>1); undef %z; print scalar(keys %z);', '0', 'hash' ] ) {
        my ( $src, $want, $label ) = $case->@*;
        my ( $out, $w, $err ) = run_and_translate( $src, "undef-agg-$label" );
        is $out, $want, "perl empties the $label";
        ok $w, "... and B::SoN lowers it ($label)" or diag($err);
    }
};

done_testing;
