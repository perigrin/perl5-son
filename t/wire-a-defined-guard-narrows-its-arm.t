# ABOUTME: `defined X && X` reads X only where it is defined, so X there is T, not
# ABOUTME: Maybe[T]: the && is join(Boolean, T) -- Boolean for a print's value.

use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir( CLEANUP => 1 );

sub stamps_of ( $src, $op ) {
    my $file = "$dir/p.pl";
    open my $fh, '>', $file or die $!;
    print {$fh} $src;
    close $fh;
    my $w = JSON::PP->new->decode( scalar qx{$^X -Ilib -MO=-q,SoN,json $file 2>/dev/null} );
    return map { $_->{stamp} // 'none' }
        grep { ( $_->{op} // '' ) eq $op } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
}

# Measured: `defined $r && $r` is "" (perl's false) or $r's own value; never undef.
is_deeply [ stamps_of( 'my $r = print NOWHERE "x"; my $x = defined $r && $r; print defined($x) ? "d" : "u";', 'And' ) ],
    ['Boolean'], 'defined X && X, X a Maybe[Boolean]: Boolean';

# Not narrowed where the guard is not on the same value.
is_deeply [ stamps_of( 'my $r = print NOWHERE "x"; my $q = print NOWHERE "y"; my $x = defined $q && $r; print defined($x) ? "d" : "u";', 'And' ) ],
    ['Maybe[Boolean]'], 'defined Y && X: X keeps its Maybe';

# The true arm of a ternary reads X where it is defined: join(T, else).
is_deeply [ stamps_of( 'my $r = print NOWHERE "x"; my $x = defined $r ? $r : !1; print defined($x) ? "d" : "u";', 'TernaryExpr' ) ],
    ['Boolean', 'Str'], 'defined X ? X : !1, X a Maybe[Boolean]: Boolean';
is_deeply [ stamps_of( 'my $r = print NOWHERE "x"; my $q = print NOWHERE "y"; my $x = defined $q ? $r : !1; print defined($x) ? "d" : "u";', 'TernaryExpr' ) ],
    ['Maybe[Boolean]', 'Str'], 'defined Y ? X : !1: X keeps its Maybe';

done_testing;
