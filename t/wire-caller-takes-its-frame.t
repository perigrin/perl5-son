# ABOUTME: caller(N) carries N on the wire; a bare caller takes nothing. The
# ABOUTME: argument was left on the stack, so caller(1) and caller read the same.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $fh "sub f { my \@a = caller; my \@b = caller(1); my \$n = 2; my \@c = caller(\$n); print \"\@a\@b\@c\\n\" }\nf();\n";
close $fh;
my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null) );
my @n = @{ $w->{methods}{'main::f'}{nodes} };
my %by = map { $_->{id} => $_ } @n;
my @callers = grep { $_->{op} eq 'Call' && $_->{fields}{name} eq 'caller' } @n;
is scalar @callers, 3, 'three callers';
is_deeply [ map { scalar @{ $_->{inputs} } } @callers ], [ 0, 1, 1 ], 'caller takes nothing, caller(1) and caller($n) their frame';
is $by{ $callers[1]{inputs}[0] }{fields}{value}, 1, '... caller(1) its 1';
done_testing;
