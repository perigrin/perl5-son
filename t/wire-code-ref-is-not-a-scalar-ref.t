# ABOUTME: \&NAME is a CodeRef; the gv name Constant must be restamped Code.
# ABOUTME: left as Str it makes the Ref rule answer ScalarRef -- a wrong kind.
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
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $wire, $method ) {
    return ( ( $wire->{methods}{$method} // {} )->{nodes} // [] );
}

# THE DEFECT, and it is the SAME ONE `rv2gv` already fixed for `\*STDOUT`.
# The gv handler pushes a glob's NAME as a Str Constant -- right where a name
# is wanted (naming a callee), a fabrication where the referent is the value.
# Measured, the optree draws the distinction with a sibling op:
#
#     foo()       gv[IV \&main::foo] -> entersub              no rv2cv
#     \&SRC       gv[IV \&main::SRC] -> rv2cv -> srefgen      rv2cv
#     \*STDOUT    gv[*STDOUT]        -> rv2gv -> srefgen      rv2gv
#
# so `rv2cv` is to code what `rv2gv` is to globs. Without it the name Constant
# stays Str, and B::SoN's Ref rule -- "the reference kind follows the operand's
# kind" -- correctly concludes ScalarRef from what it was handed:
#
#     our $x = \&SRC   ->   Ref ScalarRef [Constant Str "SRC"]
#
# A reference to a SUB described as a reference to a STRING is wrong in KIND,
# not in width: nothing downstream can call it.
subtest '\&NAME is a CodeRef, not a ScalarRef' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'coderef' );
sub SRC { "code" }
our $x = \&SRC;
SRC
    ok $wire, 'it translates' or diag($err), return;

    my ($ref) = grep { ( $_->{op} // '' ) eq 'Ref' }
        nodes( $wire, 'main::__PROGRAM__' )->@*;
    ok $ref, 'a Ref node is in the graph' or return;
    is $ref->{stamp}, 'CodeRef', 'and it is stamped CodeRef';
};

# THE NAME IS KEPT, NOT DISCARDED -- the same rule rv2gv states. There is no
# address at compile time, so the name is the only handle on WHICH sub this is
# and a consumer needs it to resolve the reference. What changes is the claim
# about its TYPE.
subtest 'the sub name survives the restamp' => sub {
    my ( $wire, undef ) = translate( <<'SRC', 'coderef-name' );
sub SRC { "code" }
our $x = \&SRC;
SRC
    ok $wire, 'it translates' or return;

    my @n = nodes( $wire, 'main::__PROGRAM__' )->@*;
    my %by = map { $_->{id} => $_ } @n;
    my ($ref) = grep { ( $_->{op} // '' ) eq 'Ref' } @n;
    ok $ref, 'a Ref node is in the graph' or return;

    my $inner = $by{ ( $ref->{inputs} // [] )->[0] // -1 };
    ok $inner, 'its operand resolves' or return;
    is $inner->{fields}{value}, 'SRC', 'the sub name is still there';
    is $inner->{stamp}, 'Code', '... carried as Code rather than Str';
};

# A CALL IS UNTOUCHED. `foo()` has no rv2cv in its exec path, so the name it
# needs is still a name -- this is the guard against fixing the reference by
# breaking every call.
subtest 'a plain call still names its callee' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'plain-call' );
sub SRC { "code" }
my $v = SRC();
SRC
    ok $wire, 'it translates' or diag($err), return;

    my ($call) = grep { ( $_->{op} // '' ) eq 'Call' }
        nodes( $wire, 'main::__PROGRAM__' )->@*;
    ok $call, 'a Call node is in the graph' or return;
    is $call->{fields}{name}, 'main::SRC', 'and it still names its callee';
};

# A SCALAR REFERENCE IS UNCHANGED: `\$q` has neither rv2cv nor rv2gv, and it
# is the case the ScalarRef default exists for.
subtest 'a scalar reference is still a ScalarRef' => sub {
    my ( $wire, undef ) = translate( 'our $q = 1; our $z = \$q;', 'scalarref' );
    ok $wire, 'it translates' or return;

    my ($ref) = grep { ( $_->{op} // '' ) eq 'Ref' }
        nodes( $wire, 'main::__PROGRAM__' )->@*;
    ok $ref, 'a Ref node is in the graph' or return;
    is $ref->{stamp}, 'ScalarRef', 'and it is still a ScalarRef';
};

done_testing;
