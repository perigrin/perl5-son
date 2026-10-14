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

# What the body cannot reach yet refuses rather than reading the wrong thing.
refuses(q{my $s = "aaa"; my $n = 0; $s =~ s/a/ $n++ /ge; print "$s $n\n";},
    qr/GAP: s\/\/\/ge whose replacement has an effect/,
    'a replacement with an effect');
refuses(q{my $k = 3; my $s = "a1b2"; $s =~ s/(\d)/$1*$k/ge; print "$s\n";},
    qr/GAP: a s\/\/\/ge replacement that reads a lexical of its enclosing scope \(\$k\)/,
    'a replacement reading an enclosing lexical');

done_testing;
