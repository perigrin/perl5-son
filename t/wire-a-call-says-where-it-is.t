# ABOUTME: every call to a sub carries its statement's file, line and package on the
# ABOUTME: wire: what `caller` in the callee answers (Test::Chalk's "at FILE line N").
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $fh "sub f { 1 }\nf();\npackage P;\nmain::f();\nP->can('x');\n";
close $fh;
my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null) );
my @calls = grep { $_->{op} eq 'Call' && ( $_->{fields}{dispatch_kind} // '' ) ne 'builtin' }
    @{ $w->{methods}{'main::__PROGRAM__'}{nodes} };
is_deeply [ map { [ @{ $_->{fields} }{qw(file line package)} ] } @calls ],
    [ [ $pl, 2, 'main' ], [ $pl, 4, 'P' ], [ $pl, 5, 'P' ] ],
    'a direct call and a method call each say their file, line and package';
done_testing;
