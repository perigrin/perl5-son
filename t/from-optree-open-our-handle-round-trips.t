# ABOUTME: `open our $T` must fill the handle, not become the store target for
# ABOUTME: the next value read through it; `open my $T` already round-trips.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

# A FIXED-WIDTH PAYLOAD, so a length check distinguishes "read the line" from
# "read something". 40 characters is what perl's own t/base/rs.t uses.
my $data = "$dir/foo";
open my $seed, '>', $data or die $!;
print $seed '1234567890123456789012345678901234567890';
close $seed;

sub write_tmp ($src, $tag) {
    my $f = "$dir/$tag." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub graph_of ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    return eval { JSON::PP->new->decode($j) };
}

sub emit ($src) {
    my $data = graph_of($src) or return ( undef, 'no graph' );
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

sub read_through ($decl) {
    return <<"SRC";
{
    if (open $decl \$T, "$data") {
        my \$line = <\$T>;
        print "# \$line\\n";
        length(\$line) == 40 or print "not ";
        close \$T or print "not ";
    }
    else { print "not " }
    print "ok 1 # $decl handle\\n";
}
SRC
}

# `open my \$T` HAS NO EntryWrite AT ALL and comes out right. `open our \$T`
# takes the package slot as the ASSIGNMENT TARGET of the readline, so the LINE
# is stored into \$T, `close` is handed that value rather than the handle, and
# the `my \$line` binding is lost. Measured:
#
#     perl   # 1234...7890 / ok 1
#     ours   # (empty)     / not not ok 1
#
# with the emission storing `\$main::T = \$eff9` and calling `close(\$eff9)`.
#
# See docs/plans/2026-09-26-open-our-handle-stores-the-line.md. The four
# symptoms are one cause, and the `my` control below is what says the defect is
# in the PACKAGE lvalue path rather than in open, readline or close.
todo 'open our $T takes the package slot as a store target' => sub {
    subtest 'an our handle reads its file' => sub {
        my $src = read_through('our');
        my ( $out, $why ) = emit($src);
        ok defined $out, 'renders' or do { diag $why; return };
        is runs($out), runs($src), 'the line comes back whole'
            or diag $out;
    };
};

# THE CONTROL. Same program, one word different, and it must keep working.
subtest 'a my handle reads its file' => sub {
    my $src = read_through('my');
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'the line comes back whole'
        or diag $out;
};

done_testing;
