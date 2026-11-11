# ABOUTME: exit carries its status on the wire whatever expression gives it; one
# ABOUTME: under a null op (a ternary) was skipped as "no child" and exited 0.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

for my $case ( [ 'exit;', 0 ], [ 'exit 3;', 1 ], [ 'our $F = 2; exit($F > 254 ? 254 : $F);', 1 ], [ 'my $n = $ENV{N}; exit($n // 4);', 1 ] ) {
    my ( $src, $want ) = @$case;
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh "$src\n"; close $fh;
    my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null) );
    my ($exit) = grep { $_->{op} eq 'Call' && $_->{fields}{name} eq 'exit' } @{ $w->{methods}{'main::__PROGRAM__'}{nodes} };
    is scalar @{ $exit->{inputs} // [] }, $want, "exit's inputs: $src";
}
done_testing;
