# ABOUTME: $1 and friends are scoped to their block: after the block ends a capture reads the
# ABOUTME: match made before it, not one made inside (final audit 2026-11-24, class I).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub translate ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die $!;
    return ( (eval { decode_json($json) }), join '', <$e> );
}

# The patterns of the matches the program's captures read (sorted, once each).
sub captured ($w) {
    my $g = $w->{methods}{'main::__PROGRAM__'} or return 'no program';
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my %p = map { ( $by{ $_->{inputs}[0] }{fields}{pattern} // '?' ) => 1 }
        grep { $_->{op} eq 'RegexCapture' } $g->{nodes}->@*;
    return join ' ', sort keys %p;
}

for my $c (
    [ '"ab"=~/(a)/; { "xy"=~/(y)/; } print "$1\n";',                          '(a)' ],
    [ '"ab"=~/(a)/; if (1) { "xy"=~/(y)/; } print "$1\n";',                   '(a)' ],
    [ 'my $c=1; "ab"=~/(a)/; if ($c) { "xy"=~/(y)/; } print "$1\n";',         '(a)' ],
    [ '"ab"=~/(a)/; my $t = do { "xy"=~/(y)/; $1 }; print "$t$1\n";',         '(a) (y)' ],
    [ '"ab"=~/(a)/; { "xy"=~/(y)/; print $1; } print "$1\n";',                '(a) (y)' ],
    [ 'my $s="abc"; $s=~/(b)/; my $x=$1; { "q"=~/(q)/; } print "$x$1\n";',    '(b)' ],
    # (no block: the later match is the one read)
    [ '"ab"=~/(a)/; "xy"=~/(y)/; print "$1\n";',                              '(y)' ],
) {
    my ( $src, $want ) = @$c;
    my ( $w, $err ) = translate($src);
    is captured($w // {}), $want, $src or diag $err;
}

done_testing;
