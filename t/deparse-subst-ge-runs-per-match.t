# ABOUTME: s///ge runs its replacement once per match, so the replacement is a body
# ABOUTME: the substitution calls, not a value; shapes it cannot lower refuse by name.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}



sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

# The chalk shape (BNF::Target::C, BNF::Target::XS, Perl::Target::EmitHelpers):
# escape every byte outside printable ASCII, one sprintf per match.
round_trips(q{use v5.36; sub esc ($s) { $s =~ s/([^\x20-\x7E])/sprintf("\\\\x%02x", ord($1))/ge; return $s } print esc("a\tb\x01c\x7f"), "\n";},
    'a sub escaping each unprintable byte');
round_trips(q{use v5.36; use experimental 'class'; class E { method esc ($str) { $str =~ s/\t/ /g; $str =~ s/([^\x20-\x7E])/sprintf("\\\\x%02x", ord($1))/ge; return $str } } print E->new->esc("x\ty\n\0z"), "\n";},
    'a method escaping each unprintable byte');
round_trips(q{use v5.36; my sub c_string ($s) { $s =~ s/([^\x20-\x7E])/sprintf("\\\\x%02x", ord($1))/ge; return qq{"$s"} } sub emit { return join ', ', map { c_string($_) } @_ } print emit("a\tb", "\x01"), "\n";},
    'a lexical sub called from another sub');

# Each match sees its OWN capture: a once-only lowering gives a10b10c.
round_trips(q{my $s = "a1b2c"; $s =~ s/(\d)/$1*10/ge; print "$s\n";},
    'the capture differs per match');
round_trips(q{my $s = "x"; $s =~ s/(\d)/$1*10/ge; print "[$s]\n";},
    'no match leaves the subject alone');
round_trips(q{my $s = "a1b22c"; my $n = ($s =~ s/(\d)/"<$1>"/ge); print "$n $s\n";},
    'the count of a /ge substitution');
round_trips(q{our $g = "p1q2"; $g =~ s/(\d)/$1+1/ge; print "$g\n";},
    'a package subject');
round_trips(q{my @l = ("a1b2c", "9"); for (@l) { s/(\d)/$1*10/ge } print "@l\n";},
    'in a foreach over the topic');
round_trips(q{my $s = "a1b2c"; for my $i (1, 2) { $s =~ s/(\d+)/$1*10/ge } print "$s\n";},
    'in a counted loop over a lexical');

# A body inside an anon sub carries `__ANON__` in its key and is named by its
# substitution or its sort, not by a Call -- it must not be taken for an orphan.
round_trips(q{my $f = sub { my $s = shift; $s =~ s/(\d)/$1*10/ge; $s }; print $f->("a1b2"), "\n";},
    'a /ge body inside an anon sub');
round_trips(q{my $f = sub { join ",", sort { my $x = $a; $x <=> $b } @_ }; print $f->(3,1,2), "\n";},
    'a comparator block inside an anon sub');

# A LONE VARIABLE REPLACEMENT has no substcont: perl stacks it on the subst
# (PMf_CONST), and it was dropped -- ab for perl's aQbQ. It is still read once
# per match: a match variable gives that match's value.
round_trips(q{our $x = "Q"; my $s = "a1b2"; $s =~ s/(\d)/$x/ge; print "$s\n";},
    'a lone package scalar replacement');
round_trips(q{our $x = "Q"; my $s = "a1b2"; my $t = $s =~ s/(\d)/$x/ger; print "$t $s\n";},
    'a lone package scalar replacement under /r');
round_trips(q{our $x = "Q"; sub f { my $s = shift; $s =~ s/(\d)/$x/ge; $s } print f("a1b2"), "\n";},
    'a lone package scalar replacement in a sub');
round_trips(q{our $x = "Q"; our $s = "a1b2"; $s =~ s/(\d)/$x/ge; print "$s\n";},
    'a lone package scalar replacement on a package subject');
round_trips(q{our $s = "a1b2"; $s =~ s/(\d)/$s/ge; print "$s\n";},
    'the subject as its own replacement');
round_trips(q{my $s = "a1b2"; $s =~ s/(\d)/$&/ge; print "$s\n";},
    'a lone $& replacement');
round_trips(q{my $s = "a1b2"; $s =~ s/(\d)/$`/ge; print "$s\n";},
    'a lone prematch replacement');
refuses(q{my $s = "a1b2"; $s =~ s/(\d)/$1/ge; print "$s\n";},
    qr/GAP: capture \$1 inside a s\/\/\/e replacement reads the substitution's OWN match/,
    'a lone capture replacement, read by the main chain before the subst');
round_trips(q{our $x = "Q"; my @l = ("a1", "b2"); for (@l) { s/(\d)/$x/ge } print "@l\n";},
    'a lone package scalar replacement in a loop');
round_trips(q{our $x = "Q"; $_ = "a1b2"; s/(\d)/$x/ge; print "$_\n";},
    'a lone package scalar replacement on $_, which is not the subject');
refuses(q{my $y = "Q"; my $s = "a1b2"; $s =~ s/(\d)/$y/ge; print "$s\n";},
    qr/GAP: a s\/\/\/ge replacement that reads a lexical of its enclosing scope \(\$y\)/,
    'a lone enclosing lexical replacement');
refuses(q{our @a = (1, 2); my $s = "a1b2"; $s =~ s/(\d)/@a/ge; print "$s\n";},
    qr/GAP: s\/\/\/ge whose replacement is a lone array or hash/, 'a lone array replacement');

# What the body cannot reach yet refuses rather than reading the wrong thing.
refuses(q{my $s = "aaa"; my $n = 0; $s =~ s/a/ $n++ /ge; print "$s $n\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/,
    'a replacement with an effect');
refuses(q{my $k = 3; my $s = "a1b2"; $s =~ s/(\d)/$1*$k/ge; print "$s\n";},
    qr/GAP: a s\/\/\/ge replacement that reads a lexical of its enclosing scope \(\$k\)/,
    'a replacement reading an enclosing lexical');

# An ASSIGN-OP stores into its operand -- `$n += $1` is add with OPf_STACKED --
# so it is an effect, and lowering it re-evaluated the sum for the value
# (a2b5 for perl's a1b3).
refuses(q{our $n = 0; my $s = "a1b2"; $s =~ s/(\d)/$n += $1/ge; print "$s $n\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a += into a package scalar');
refuses(q{our $k = "z"; my $s = "a1b2"; $s =~ s/(\d)/$k .= $1/ge; print "$s $k\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a .= into a package scalar');
refuses(q{our $n = 1; my $s = "a1b2"; $s =~ s/(\d)/$main::n *= $1/ge; print "$s $n\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a *= into a qualified package scalar');
refuses(q{our $n = 0; my $s = "a1b2"; $s =~ s/(\d)/($n -= $1) . "x"/ge; print "$s $n\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a -= nested in the value');
refuses(q{our $z = ""; my $s = "a1b2"; $s =~ s/(\d)/$main::z .= $1; "y"/ge; print "$s $z\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a .= as a statement before the value');

# A string STORE into a package scalar is multiconcat with OPf_STACKED -- an
# UNOP_AUX, not a binop -- and lowering it read the target where the capture
# belonged (azxxbzxxx zxx for perl's a1xb2x 2x).
refuses(q{our $k = "z"; my $s = "a1b2"; $s =~ s/(\d)/$k = $1 . "x"/ge; print "$s $k\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a string assign into a package scalar');
refuses(q{our $k = "z"; my $s = "a1b2"; $s =~ s/(\d)/$k = "<$1>"/ge; print "$s $k\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'an interpolated assign into a package scalar');
refuses(q{our $k = "z"; my $s = "a1b2"; $s =~ s/(\d)/$k .= "<$1>"/ge; print "$s $k\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'an interpolated append into a package scalar');
refuses(q{our $k = "z"; my $s = "a1b2"; $s =~ s/(\d)/$k .= $1 . $1/ge; print "$s $k\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a concat append into a package scalar');
refuses(q{our $k = "z"; my $s = "a1b2"; $s =~ s/(\d)/($k = "[$1]") . "!"/ge; print "$s $k\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a string assign nested in the value');
refuses(q{our $k = "z"; my $s = "a1b2"; $s =~ s/(\d)/$main::k = "$1-"/ge; print "$s $k\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/, 'a string assign into a qualified package scalar');

# The SUBJECT must be a plain scalar variable: an element, a deref or a field
# fell back to $_ (the subject is lost, a1b2 for perl's a3b6).
my $target = qr/GAP: s\/\/\/ge on a subject that is not a plain scalar variable/;
refuses(q{my %h = (x => "a1b2"); $h{x} =~ s/(\d)/$1*3/ge; print "$h{x}\n";},
    $target, 'a hash element subject');
refuses(q{my @a = ("a1b2"); $a[0] =~ s/(\d)/$1*3/ge; print "$a[0]\n";},
    $target, 'an array element subject');
refuses(q{my $x = "a1b2"; my $r = \$x; $$r =~ s/(\d)/$1*3/ge; print "$x\n";},
    $target, 'a scalar deref subject');
refuses(q{our %h = (x => "a1b2"); $main::h{x} =~ s/(\d)/$1*3/ge; print "$h{x}\n";},
    $target, 'a package hash element subject');
refuses(q{my $o = {k => "a1b2"}; $o->{k} =~ s/(\d)/$1*3/ge; print "$o->{k}\n";},
    $target, 'an arrow element subject');
refuses(q{use v5.38; use experimental 'class'; class C { field $f = "a1b2"; method m { $f =~ s/(\d)/$1*5/ge; return $f } } print C->new->m, "\n";},
    $target, 'a field subject');

# An INTERPOLATED PATTERN rendered as an empty one, so $1 read nothing.
my $pat = qr/GAP: s\/\/\/ge with an interpolated pattern/;
refuses(q{my $re = qr/(\d)/; my $s = "a1b2"; $s =~ s/$re/$1*2/ge; print "$s\n";},
    $pat, 'a qr// pattern');
refuses(q{my $d = '\d'; my $s = "a1b2"; $s =~ s/($d)/$1*2/ge; print "$s\n";},
    $pat, 'a pattern interpolating a lexical');
refuses(q{our $d = '\d'; my $s = "a1b2"; $s =~ s/x|($d)/$1*2/ge; print "$s\n";},
    $pat, 'a pattern interpolating a package scalar');

# A /ge BODY UNDER /n: the flag reaches the substitution, so the body's $1
# reads nothing (a2b4 for perl's a0b0). More /n cases sit with the other
# pattern flags.
round_trips(q{my $s = "a1b2"; $s =~ s/(\d)/$1*2/gen; print "[$s]\n";},
    'a body under /n');

# A PRECEDING MATCH leaves pos and captures that the /ge does not read.
round_trips(q{my $s = "a1b2"; $s =~ /(\d)/; $s =~ s/(\d)/$1*2/ge; print "$1 $s\n";},
    'after a match that set $1');
round_trips(q{my $s = "a1b2"; $s =~ /\d/g; $s =~ s/(\d)/$1*2/ge; print pos($s) // "u", " $s\n";},
    'after a /g match that set pos');
round_trips(q{my $s = "a1b2"; my @r = ($s =~ s/(\d)/$1*2/ge); print "@r $s\n";},
    'in list context');
round_trips(q{my $s = "a1b2"; my $t = $s =~ s/(\d)/$1*2/ger; print "$t $s\n";},
    'under /r');
round_trips(q{my @a = ("a1", "b2"); s/(\d)/$1*2/ge for @a; print "@a\n";},
    'aliasing the topic in a postfix for');

# A COPY TAKEN BEFORE AN IN-PLACE REWRITE keeps the old string. The subject
# is a demoted slot, so the copy is a read at the version before the rewrite,
# and spelled by name after it, it read the rewritten string (a2b4 a2b4).
round_trips(q{my $s="a1b2"; my $t=$s; $s =~ s/(\d)/$1*2/ge; print "$s $t\n";},
    'a copy before the substitution');
round_trips(q{sub f { my $s=shift; my $t=$s; $s =~ s/(\d)/$1*2/ge; "$s $t" } print f("a1b2"),"\n";},
    'a copy before the substitution in a sub');
round_trips(q{my $s="a1b2"; my @a=($s); $s =~ s/(\d)/$1*2/ge; print "@a $s\n";},
    'an array element copied before the substitution');
round_trips(q{my $s="a1b2"; my $t="$s"; $s =~ s/(\d)/$1*2/ge; print "$s $t\n";},
    'an interpolated copy before the substitution');
round_trips(q{my $s="a1b2"; my $t; $t=$s; $s =~ s/(\d)/$1*2/ge; $t .= ""; print "$s $t\n";},
    'an assigned copy appended to after the substitution');
round_trips(q{my $s="a1b2"; my $t=$s; $s =~ s/(\d)/X/g; print "$s $t\n";},
    'a copy before a literal /g substitution');
round_trips(q{my $s="a1b2"; my $t=$s; $s =~ s/(\d)/$1*2/e; print "$s $t\n";},
    'a copy before a /e substitution');
round_trips(q{my $s="a1b2"; my $t=$s; $s =~ tr/a/b/; print "$s $t\n";},
    'a copy before a transliteration');
round_trips(q{my $s="a1b2"; my $t=$s; my $u = $s =~ s/(\d)/$1*2/ger; print "$s $t $u\n";},
    'a copy beside a /r substitution');
round_trips(q{my @a=("a1","b2"); my @b = map { s/(\d)/$1*2/ge; $_ } @a; print "@a|@b\n";},
    'map aliasing the topic into the array');

round_trips(q{my $s="a1b2"; my $t=$s; my $u=$s; my $n = ($s =~ s/(\d)/$1*2/ge); print "$n $s $t $u\n";},
    'two copies before a counted substitution');
round_trips(q{my $s="a1b2"; my $t=$s; if ($s =~ /(\d)/) { print "$1\n" } $s =~ s/(\d)/X/; print "$s $t\n";},
    'a copy read past a match before the substitution');
round_trips(q{my $s="a1"; my $t=$s; $s =~ s/1/X/ if 1; print "$s $t\n";},
    'a copy before a substitution under a folded condition');

done_testing;
