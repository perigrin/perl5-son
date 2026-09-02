# ABOUTME: A `#line` directive renames a CV's FILE; subs after one must still be
# ABOUTME: emitted, and modules loaded alongside the producer must still not be.

use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

# WHICH FILE WE WERE ASKED TO COMPILE is the right question -- the sub walk
# reads the symbol table, and the producer's own dependencies (JSON::PP, Carp,
# B::SoN itself: 501 translatable CVs) sit in the same interpreter. Scoping by
# PACKAGE would break self-hosting, so the test is by file.
#
# But `$file eq $0` asks each CV where IT thinks it came from, and a `#line`
# directive is source-controlled text that rewrites exactly that. base/lex.t
# TESTS the directive:
#
#     # line 42 "plink"
#
# so every sub defined below it reported FILE=plink and was dropped -- with no
# GAP and no warning, which is the silent-drop class this contract exists to
# prevent. The anchor is the FIRST COP of the program, which carries the real
# filename before any directive takes effect.

subtest 'subs after a #line directive are still emitted' => sub {
    my ( $w, $err ) = translate( <<'SRC', 'line-directive' );
my $x = 1;
sub above { 1 }
# line 42 "plink"
sub below { 2 }
print above() + below();
SRC
    ok $w, 'it translates' or do { diag($err); return };

    my %m = ( $w->{methods} // {} )->%*;
    ok exists $m{'main::above'}, 'a sub BEFORE the directive is emitted';
    ok exists $m{'main::below'},
        'a sub AFTER the directive is emitted too -- the file lied, not the sub';
};

# THE FILTER MUST STILL FILTER. Dropping it entirely would pull in the
# producer's own dependencies, which is what it exists to prevent.
subtest 'modules loaded alongside the producer are still excluded' => sub {
    my ( $w, $err ) = translate( 'my $x = 1; print $x;', 'no-leak' );
    ok $w, 'it translates' or do { diag($err); return };

    my @leaked = grep { /^(?:JSON::PP|Carp|B::SoN|SoN::)/ }
        keys( ( $w->{methods} // {} )->%* );
    is scalar(@leaked), 0, 'no producer or dependency graphs leaked'
        or diag( "leaked: " . join( ', ', @leaked ) );
};

# A PACKAGE NAME WITH EMPTY COMPONENTS IS STILL A PACKAGE. perl's lexer
# accepts `sub foo::::::bar {...}` and puts it in a real stash whose
# intermediate components are literally `::`:
#
#     foo::        keys=[::]
#     foo::::      keys=[::]
#     foo::::::    keys=[bar]
#
# base/lex.t tests exactly this, and B::SoN leverages the same lexer -- so a
# recursion guard of `[A-Za-z_]\w*::` refuses to descend into a package perl
# itself created, and the sub disappears with no GAP and no warning.
subtest 'a package with empty name components is walked' => sub {
    my ( $w, $err ) = translate(
        'sub foo::::::bar { 7 } print foo::::::bar();', 'empty-components' );
    ok $w, 'it translates' or do { diag($err); return };

    my %m = ( $w->{methods} // {} )->%*;
    ok scalar( grep { /bar\z/ } keys %m ),
        'the sub in the empty-component package is emitted'
        or diag( 'methods: ' . join( ', ', sort keys %m ) );
};

# ORDINARY NESTING IS UNAFFECTED -- a fix that loosened the guard into matching
# anything would start walking non-package keys.
subtest 'an ordinary nested package still works' => sub {
    my ( $w, $err ) = translate(
        'sub Foo::Bar::baz { 3 } print Foo::Bar::baz();', 'nested-ok' );
    ok $w, 'it translates' or do { diag($err); return };
    ok scalar( grep { /baz\z/ } keys( ( $w->{methods} // {} )->%* ) ),
        'a normally-nested sub is emitted';
};

done_testing;
