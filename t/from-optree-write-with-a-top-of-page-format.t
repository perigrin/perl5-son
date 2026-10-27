# ABOUTME: `write` on a handle that has a top-of-page format is refused: perl prints
# ABOUTME: that format first, and the graph would print the body alone.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub son_stderr ($src) {
    my $f = "$dir/w." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $err = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
    unlink $f;
    return $err;
}

like(son_stderr("format STDOUT_TOP =\nHEAD\n.\nformat STDOUT =\nbody\n.\nwrite;\n"),
    qr/GAP: .*top-of-page format/, 'a top-of-page format refuses the write');
unlike(son_stderr("format STDOUT =\nbody\n.\nwrite;\n"),
    qr/GAP/, 'no top-of-page format: the write is lowered');

done_testing;
