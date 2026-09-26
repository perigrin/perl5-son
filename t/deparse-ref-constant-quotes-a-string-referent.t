# ABOUTME: a folded `\"text"` records the REFERENT, so the referent needs the
# ABOUTME: same quoting a string constant gets -- raw, it is not even Perl.
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

# PERL FOLDS `\"x\n"` TO A SINGLE REF CONSTANT. Measured, the producer records
#
#     Constant const_type=ref value="x\n"
#
# -- the VALUE is the referent, not the reference, which is why the renderer
# supplies the backslash. It supplied it and nothing else, so a string referent
# came out unquoted:
#
#     open($fh, "<", \x
#     );
#
# That is not Perl. A NUMERIC referent is fine bare (`$/ = \2`, the fixed-size
# record separator, is the case the renderer was written for), so the defect
# only appears when the referent is text -- which is exactly the in-memory
# filehandle idiom the corpus uses for every handle it opens.

subtest 'a reference to a string constant' => sub {
    my $src = <<'SRC';
open(my $fh, "<", \"x\n");
print "opened\n";
close($fh);
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };

    my $f = write_tmp( $out, 'c' );
    my $chk = qx($^X -c $f 2>&1);
    unlink $f;
    like $chk, qr/syntax OK/, 'the emission compiles' or diag "$chk\n$out";

    is runs($out), runs($src), 'and it prints what perl prints' or diag $out;
};

# READ THROUGH, not merely opened: a handle that opens and yields nothing would
# pass the case above.
subtest 'an in-memory handle is actually readable' => sub {
    my $src = <<'SRC';
open(my $fh, "<", \"one\ntwo\n");
my $line = <$fh>;
print $line;
close($fh);
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'the first line comes back' or diag $out;
};

# A NUMERIC REFERENT MUST STAY BARE. `$/ = \2` reads fixed-size records, and
# quoting the 2 would set the separator to the STRING "2" -- a program that
# runs and reads different records. This is the case the renderer was built
# for and the regression guard for the fix.
subtest 'a reference to a number is not quoted' => sub {
    my $src = <<'SRC';
open(my $fh, "<", \"abcdefgh");
local $/ = \3;
my $rec = <$fh>;
print "[$rec]\n";
close($fh);
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'fixed-size records still read' or diag $out;
};

done_testing;
