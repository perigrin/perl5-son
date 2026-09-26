# ABOUTME: two calls flattened into one list each bind a temporary, and the
# ABOUTME: second binding must be emitted BEFORE the list that reads it.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub write_tmp ($src, $tag) {
    my $f = "$dir/$tag." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub emit ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    my $data = eval { JSON::PP->new->decode($j) } or return ( undef, 'no graph' );
    return ( undef, 'no program' ) unless $data->{methods}{'main::__PROGRAM__'};
    my $out = eval { SoN::Deparse->new->render($data) };
    return ( undef, ( $@ || 'refused' ) ) unless defined $out;
    return ( $out, undef );
}

sub runs ($src) {
    my $f = write_tmp( $src, 'r' );
    my $o = qx($^X $f 2>&1);
    unlink $f;
    return $o;
}

# A LIST-RETURNING CALL FLATTENS, so two of them in one list contribute four
# elements. Measured:
#
#     sub two { return (1, 2) }
#     my @r = (two(0), two(0));   scalar(@r) is 4
#
# Each call is bound to its own array temporary -- correct, because a call read
# twice would RUN twice -- but the emission placed the second binding AFTER the
# list that reads it:
#
#     my @eff3 = two(0);
#     my @r = (@eff3, @eff4);     <- @eff4 is the empty PACKAGE array here
#     my @eff4 = two(0);
#
# It COMPILES (no strict), and `perl -w` says only "Name "main::eff4" used only
# once: possible typo". The program printed 2 where perl prints 4 -- a silent
# wrong answer, in the path that does NOT refuse.

subtest 'two list-returning calls in one list' => sub {
    my $src = <<'SRC';
sub two { return (1, 2) }
my @r = (two(0), two(0));
print scalar(@r), "\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };

    # STRICT IS THE DIAGNOSTIC. Without it a read-before-declaration silently
    # reads an empty package array; under strict it is a hard error naming the
    # variable, which is what makes the failure legible rather than numeric.
    my $f = write_tmp( "use strict; use warnings;\n$out", 'c' );
    my $chk = qx($^X -c $f 2>&1);
    unlink $f;
    like $chk, qr/syntax OK/,
        'every binding is declared before it is read' or diag "$chk\n$out";

    is runs($out), runs($src), 'and four elements reach the list' or diag $out;
};

# ONE CALL IS THE CONTROL: it cannot expose an ordering defect, because there is
# no second binding to misplace. A fix that passed only this would be untested.
subtest 'one list-returning call still flattens' => sub {
    my $src = <<'SRC';
sub two { return (1, 2) }
my @r = (two(0), 9);
print scalar(@r), "\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'three elements' or diag $out;
};

done_testing;
