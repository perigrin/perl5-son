# ABOUTME: B::SoN follows `use`: a module the program loads has its subs on the wire
# ABOUTME: and is listed in `modules`; pragmas and the compiler's own modules are not.

use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir( CLEANUP => 1 );
mkdir "$dir/lib" or die $!;

sub write_file ( $path, $src ) {
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} $src;
    close $fh;
}

write_file( "$dir/lib/MyMod.pm", "package MyMod;\nsub f { return \$_[0] * 2 }\nsub g { my \$s = shift; \$s =~ s/(.)/ord(\$1)/ge; \$s }\n1;\n" );
write_file( "$dir/p.pl", "use strict;\nuse warnings;\nuse lib '$dir/lib';\nuse MyMod;\nprint MyMod::f(21), \"\\n\";\n" );

my $json = qx{$^X -Ilib -MO=-q,SoN,json $dir/p.pl 2>/dev/null};
my $w    = eval { JSON::PP->new->decode($json) };
ok $w, 'it translates' or BAIL_OUT("no JSON");

my @methods = sort keys %{ $w->{methods} };
ok( ( grep { $_ eq 'MyMod::f' } @methods ), 'the used module\'s sub is on the wire' )
    or diag "methods: @methods";

my %mod = map { $_->{name} => $_ } @{ $w->{modules} // [] };
is $w->{methods}{'MyMod::f'}{module} // '', 'MyMod',
    '... marked with its module, so an emitter loads it rather than re-emitting it';
ok !exists $w->{methods}{'main::__PROGRAM__'}{module}, 'the program is not marked';
my @lifted = grep { /\AMyMod::g::__SUBSTREPL__:/ } keys %{ $w->{methods} };
ok @lifted, 'a body lifted from a module sub is on the wire';
is_deeply [ map { $w->{methods}{$_}{module} // '' } @lifted ], [ map { 'MyMod' } @lifted ], '... marked with the module too';

ok $mod{MyMod}, 'MyMod is listed in modules' or diag explain $w->{modules};
like $mod{MyMod}{file} // '', qr{/lib/MyMod\.pm\z}, '... with the file it came from';

ok !$mod{strict} && !$mod{warnings} && !$mod{lib}, 'pragmas are not followed';
ok !( grep { /\A(?:B::SoN|SoN::|O::|B::)/ } @methods ), 'the compiler\'s own modules are not on the wire';
ok !( grep { /\A(?:B|O|SoN)(?:::|\z)/ } keys %mod ), 'nor listed in modules, even one B loads late (B::Op_private)'
    or diag join ' ', sort keys %mod;

# A MODULE THE COMPILER HAD ALREADY LOADED (Carp, Scalar::Util, Exporter) is
# followed when the program -- or a module it follows -- `use`s it, and only then.
my $carp_of = sub ($src) {
    write_file( "$dir/c.pl", $src );
    my $c = JSON::PP->new->decode( scalar qx{$^X -Ilib -MO=-q,SoN,json $dir/c.pl 2>/dev/null} );
    return ( ( grep { $_->{name} eq 'Carp' } @{ $c->{modules} // [] } ) ? 1 : 0, $c );
};
my ( $followed, $c ) = $carp_of->("use Carp ();\nprint \"x\\n\";\n");
ok $followed, 'a preloaded module the program uses is followed';
ok( ( grep { /\ACarp::/ } keys %{ $c->{methods} } ), '... its subs on the wire' );
($followed) = $carp_of->("print \"x\\n\";\n");
ok !$followed, 'one the program does not use is not';
write_file( "$dir/lib/UsesCarp.pm", "package UsesCarp;\nuse Carp ();\nsub f { 1 }\n1;\n" );
($followed) = $carp_of->("use lib '$dir/lib';\nuse UsesCarp;\nprint UsesCarp::f(), \"\\n\";\n");
ok $followed, 'a preloaded module a followed module uses is followed too';

# A MODULE PERL LOADS TO IMPLEMENT A BUILTIN is the builtin, not the program's
# import: glob loads File::Glob, %! loads Errno, %+ Tie::Hash::NamedCapture.
write_file( "$dir/b.pl", 'my @n = glob("*.x"); my $e = $!{ENOENT}; "a" =~ /(?<x>a)/; print $+{x}, "\n";' );
my $b = JSON::PP->new->decode( scalar qx{$^X -Ilib -MO=-q,SoN,json $dir/b.pl 2>/dev/null} );
is_deeply [ map { $_->{name} } @{ $b->{modules} // [] } ], [], 'a builtin\'s own module is not followed';
ok !( grep { /\A(?:Errno|File::Glob|Tie::Hash::NamedCapture)::/ } keys %{ $b->{methods} } ),
    '... nor its subs on the wire';

# AN IMPORTED NAME IS AN ALIAS: `use MyExp qw(g)` makes main::g the same CV as
# MyExp::g. The call names the CV's real home, where its sub is on the wire.
write_file( "$dir/lib/MyExp.pm",
    "package MyExp;\nuse Exporter 'import';\nour \@EXPORT_OK = qw(g);\nsub g { return \$_[0] + 1 }\n1;\n" );
write_file( "$dir/q.pl", "use lib '$dir/lib';\nuse MyExp qw(g);\nprint g(41), \"\\n\";\n" );
my $q = JSON::PP->new->decode( scalar qx{$^X -Ilib -MO=-q,SoN,json $dir/q.pl 2>/dev/null} );
my @calls = map { $_->{fields}{name} } grep { $_->{op} eq 'Call' } @{ $q->{methods}{'main::__PROGRAM__'}{nodes} };
is_deeply \@calls, ['MyExp::g'], 'the imported call names MyExp::g, not main::g';

done_testing;
