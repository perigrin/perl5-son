# ABOUTME: while B::SoN compiles, an XS load inside the module's own eval dies (PerlOnJava's
# ABOUTME: model), so its pure-Perl fallback is what is followed; a bare XS load still loads.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub compile_src ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    my ( undef, $err ) = tempfile( UNLINK => 1 );
    my $json = qx($^X -Ilib -MO=-q,SoN,json $pl 2>$err);
    return ( eval { decode_json($json) } // {}, do { local ( @ARGV, $/ ) = $err; <> } );
}

# Data::Dumper wraps XSLoader::load in an eval and sets $Useperl when it dies.
my ( $w, $err ) = compile_src(
    qq{use Data::Dumper;\nBEGIN { warn defined &Data::Dumper::Dumpxs ? "mode xs\\n" : "mode pp\\n" }\nprint Dumper([1]);\n} );
like $err, qr/^mode pp$/m, 'the XS load died while compiling: the fallback loaded';
# The pure-Perl path's own subs are compiled (Dumpperl itself is refused for
# its `local @x`, silently: a module's gap is reported where it is called).
ok $w->{methods}{'Data::Dumper::Dumper'} && $w->{methods}{'Data::Dumper::_quote'},
    'the fallback\'s pure-Perl subs are on the wire';
ok( ( grep { $_->{name} eq 'Data::Dumper' } @{ $w->{modules} // [] } ), 'and Data::Dumper is followed' );

# POSIX loads its XS bare: no fallback, so it loads and a call to it says xs.
( $w, $err ) = compile_src(qq{use POSIX ();\nprint POSIX::floor(\$ENV{X} // 1.5), "\\n";\n});
my ($floor) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'POSIX::floor' }
    @{ $w->{methods}{'main::__PROGRAM__'}{nodes} // [] };
ok $floor && $floor->{fields}{xs}, 'a module with no fallback still loads; its XS call says so'
    or diag $err;

done_testing;
