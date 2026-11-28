# ABOUTME: An SV perl pushes and a later operand or the consumer may store is read when its consumer
# ABOUTME: runs, or refused by name (fifth final audit, Q2-Q6, Q18): the default is the refusal.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Deparse;

# THE DEFECTS. Audit 4's X7 rule re-read the operands of the consumers it
# listed: the left operand of && || //, `scalar`, a one-statement `do`. The
# right operand, `x`, a list in a `do` block or a map body, `++$x` as a call's
# argument, `$1`, substr and `$#a` as arguments, a list assignment's value in a
# list, `\(my $v = 1)`: each read where perl pushed it, and a later store was
# lost. Each program here prints perl's answer through the deparser, or is
# refused by name; none may print another answer.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub file ($src) { my $f = "$dir/p" . ++$n . '.pl'; open my $o, '>', $f or die $!; print $o $src; close $o; $f }
sub run_perl ($src) { my $f = file($src); scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null) }

# check($src, $want) -- $want: 'same' (prints perl's answer), 'refused', or 'either'
sub check ( $src, $want ) {
    my $f   = file($src);
    my $j   = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $err = do { local ( @ARGV, $/ ) = "$dir/err"; <> } // '';
    if ( $err =~ /(GAP: .*)/ ) {
        my $gap = $1;
        return pass("refused by name: $src") if $want ne 'same';
        return fail("lowered: $src") || diag $gap;
    }
    return fail("refused: $src") if $want eq 'refused';
    my $d   = SoN::Deparse->new;
    my $out = $d->render( eval { JSON::PP->new->decode($j) } // {} );
    return pass("refused by the deparser: $src") if !defined $out && $want eq 'either';
    return fail("renders: $src") || diag( $d->gap // $err ) unless defined $out;
    is run_perl($out), run_perl($src), "perl's answer: $src" or diag $out;
}

# Q3: a pre-increment as a call's argument hands the variable
check( $_, 'same' ) for
    'my $x = 1; sub f { $_[0] . $_[1] } print f(++$x, $x++), "\n";',
    'our $x = 1; sub f { $_[0] . $_[1] } print f(++$x, $x++), "\n";',
    'my $x = 1; sub c { $x = 7; 0 } sub f { "@_" } print f(++$x, c()), "\n";',
    'my $x = 1; sub f { "@_" } print f($x, ++$x, $x++, $x), "\n";';

# Q2: && || // hand on either operand; a `do` block's list; `x`; a map body
check( $_, 'either' ) for
    'my $x = 1; my $y = 1; my @l = (($y && $x), $x = 3); print "@l\n";',
    'our $x = 1; our $y = 0; sub c { $x = 3; 2 } my @l = (($y || $x), c()); print "@l\n";',
    'my $x = 1; my $y; my @l = (($y // $x), $x++); print "@l\n";',
    'my $x = 1; my @l = do { ($x, $x++) }; print "@l\n";',
    'my $x = 1; my @l = (do { ($x, $x++) }, 0); print "@l\n";',
    'my $x = 1; my ($p, $q) = do { ($x, $x++) }; print "$p$q\n";';
check( $_, 'refused' ) for
    'my $x = 1; my @l = do { 1; ($x, $x++) }; print "@l\n";',
    'my $x = 1; sub id { "@_" } print id(do { ($x, $x++) }), "\n";',
    'my $x = 1; for my $e (do { ($x, $x++) }) { print $e } print "\n";',
    'my $x = 1; my @l = (($x) x 2, $x = 3); print "@l\n";',
    'sub f { $_[0]++; 0 } my @a = (1,2,3); my @t = map { ($_, f($_), $_) } @a; print "@t\n";';
# Q4, Q5: a magical value as an argument or an item; `$1` after s///
check( $_, 'refused' ) for
    'my $t = "a"; sub id { "@_" } print id(substr($t, 0, 1), $t = "zz"), "\n";',
    'my @t = (1,2); sub id { "@_" } print id($#t, push(@t, 3)), "\n";',
    'my $s = "abc"; $s =~ /(a)/; my @l = ($1, $s =~ /(b)/); print "@l\n";',
    'my $s = "abc"; $s =~ /(a)/; sub sh { "q" =~ /(q)/; $_[0] } print sh($1), "\n";',
    'my $s = "abc"; $s =~ /(a)/; (my $t = "x") =~ s/(x)/y/; print $1, "\n";',
    'my $s = "abc"; $s =~ /(a)/; for my $e ($1) { $s =~ /(b)/; print $e } print "\n";';
# Q6: a list assignment's value in a list is its targets, read when the list is used
check( $_, 'either' ) for
    'my ($x, $y); my @l = ((($x, $y) = (7,8)), $x = 9); print "@l\n";',
    'my ($x, $y); sub z { 0 } my @l = ((($x, $y) = (7,8)), z()); print "@l\n";',
    'my @a = (1,2,3); my @l = ((@a[0,1] = (7,8)), $a[0] = 9); print "@l\n";';
check( 'my ($x, $y); my @m = map { $x = 0; $_ } (($x, $y) = (7, 8)); print "@m\n";', 'refused' );
# Q18, Q14, Q15, Q12
check( $_, 'refused' ) for
    'my $r = \(my $v = 1); sub c { $v = 9; 0 } my @l = ($$r, c()); print "@l\n";',
    'my %h = (a=>1,b=>2,c=>3); my $k = [qw(b c)]; delete @h{@$k}; print join(",", sort keys %h), "\n";',
    'my @a = (1,2,3); $_ *= 2 for @a[1..$#a]; print "@a\n";',
    'my @a = (1,2,3); my $r = \$a[1]; @a = reverse @a; $$r = 9; print "@a\n";',
    'my @a = (1,2,3); my $r = \$a[1]; @a = @a; $$r = 9; print "@a\n";';
check( 'my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); my $l = delete @h{@k}; print "$l", scalar(keys %h), "\n";', 'same' );
# what the narrowed rules keep lowered, and what they still refuse
check( $_, 'same' ) for
    'my @l = ((my @a = (7,8)), $a[0] = 9); print "@l\n";',
    'my ($x, $y); my @l = (scalar(($x, $y) = (7,8)), $x = 9); print "@l\n";';
# (chalk prints perl's answer for these; the deparser cannot spell them: v/vr88, v/vs82)
check( $_, 'either' ) for
    'my $a = [1,2,3]; $_ *= 2 for @$a[1..$#$a]; print "@$a\n";';
check( $_, 'refused' ) for
    'my @a; sub z { $a[0] = 9; 0 } my @l = ((@a = (7,8)), z()); print "@l\n";',
    'my @a; my @l = ((@a = (7,8)), shift @a); print "@l\n";';
# A CALL WHOSE CALLEE THE WALK CANNOT NAME may be an :lvalue sub's: its value
# is the scalar it returns, read when the consumer runs (a dynamic method, a
# code ref; probes v/vu07-vu13). Where no :lvalue sub may be it, a copy.
check( $_, 'refused' ) for
    'my $x = 1; sub lv :lvalue { $x } my $m = "lv"; my @l = (main->$m(), ($x = 5)); print "@l\n";',
    'my $x = 1; sub lv :lvalue { $x } my $m = "lv"; sub f { $x = 7; $_[0] } print main->$m() . f(main->$m()), "\n";',
    'my $x = 1; sub lv :lvalue { $x } my $m = "lv"; sub f { $x = 7; print $_[0], "\n" } f(main->$m());',
    'my $x = 1; sub lv :lvalue { $x } my $c = \&lv; my @l = ($c->(), ($x = 5)); print "@l\n";',
    'package O; my $x = 1; sub new { bless {}, shift } sub lv :lvalue { $x } sub set { $x = $_[1]; 0 } package main; my $o = O->new; my @l = ($o->lv, $o->set(5)); print "@l\n";',
    'my $x = 1; my $c = sub :lvalue { $x }; sub f { $x = 7; $_[0] } print f($c->()), "\n";';
check( $_, 'same' ) for
    'my $x = 1; sub lv :lvalue { $x } my $m = "lv"; print main->$m(), "\n"; $x = 5; print main->$m(), "\n";',
    'package O; sub new { bless { n => 1 }, shift } sub n { $_[0]{n} } sub set { $_[0]{n} = $_[1]; 0 } package main; my $o = O->new; my $m = "n"; my @l = ($o->$m, $o->set(5)); print "@l ", $o->$m, "\n";';
# Q11: a store to a range iterator a reference is taken of
check( $_, 'same' ) for
    'my @r; for my $i (1..3) { $i *= 2; push @r, \$i } print join(",", map { $$_ } @r), "\n";',
    'my @r; for my $i (1..3) { $i++; push @r, \$i } print join(",", map { $$_ } @r), "\n";';

done_testing;
