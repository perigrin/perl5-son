# ABOUTME: print to a handle names the handle in the IR -- T1's job is truth.
# ABOUTME: Whether a target can honor it is T2's question, not the producer's.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub wire ( $src, $name ) {
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

# THE DEFECT. `print $fh "x"` was refused outright, on the grounds that the
# runtime-free backend writes only to stdout so honoring a handle would
# misroute. That is a T2 judgement -- can this TARGET represent a filehandle --
# made inside T1, whose only job is to say truthfully what the program does.
# The producer does not decide lowering; it states the operation and lets the
# consumer decide whether it can lower it.
#
# The optree is uniform across both spellings (measured, perl 5.42): an rv2gv
# pushes the handle, the args follow, and print carries OPf_STACKED.
#
#     print $fh "x"    padsv $fh -> rv2gv -> const "x" -> print vKS
#     print STDERR "x" gv *STDERR -> rv2gv -> const "x" -> print vKS
subtest 'print to a lexical handle names it in the graph' => sub {
    my ( $w, $err ) = wire(
        'open(my $fh, ">", "/dev/null") or die; print $fh "x";', 'lexfh' );
    ok $w, 'it translates rather than refusing' or diag($err), return;

    my ($p) = grep { ( $_->{op} // '' ) eq 'Print' } nodes($w)->@*;
    ok $p, 'a Print node exists' or return;
    ok $p->{fields}{has_filehandle},
        'the Print says it targets an explicit handle';
};

# WHICH OPERAND IS THE HANDLE must be unambiguous: inputs are positional, and a
# consumer that guesses wrong prints the handle and writes to the string.
subtest 'the handle is operand 0, ahead of the arguments' => sub {
    my ( $w, $err ) = wire( 'print STDERR "x";', 'barefh' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($p) = grep { ( $_->{op} // '' ) eq 'Print' } $ns->@*;
    ok $p, 'a Print node exists' or return;

    my @in = map { $by{$_} } ( $p->{inputs} // [] )->@*;
    ok scalar(@in) >= 2, 'handle plus at least one argument' or return;
    # BY VALUE, NOT BY TYPE. A bareword handle IS a string Constant, so
    # const_type cannot tell the two apart -- and asserting on it passed for
    # the wrong reason. The names are what discriminate.
    is( ( $in[0]{fields}{value} // '' ), 'STDERR',
        'operand 0 is the HANDLE' );
    is( ( $in[-1]{fields}{value} // '' ), 'x',
        'and the argument is still last' );
};

# PLAIN print IS UNCHANGED -- no handle operand, and nothing claiming one.
subtest 'print without a handle is untouched' => sub {
    my ( $w, $err ) = wire( 'print "x";', 'plain' );
    ok $w, 'it translates' or diag($err), return;

    my ($p) = grep { ( $_->{op} // '' ) eq 'Print' } nodes($w)->@*;
    ok $p, 'a Print node exists' or return;
    ok !$p->{fields}{has_filehandle}, 'it does not claim a handle';
    is scalar( ( $p->{inputs} // [] )->@* ), 1, 'and carries only its argument';
};

done_testing;
