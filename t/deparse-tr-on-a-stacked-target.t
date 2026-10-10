# ABOUTME: tr/// on a subject the stack supplies -- a copy made in the same statement, a
# ABOUTME: package scalar, an element, a deref -- stores into that subject; tr///r reads its targ.

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



# A tr/// whose subject is a copy of some other kind of lvalue has no lowering;
# it must refuse rather than drop the transliteration.
sub refuses ($src, $want, $name) {
    my $data = graph_of($src);
    my $d = SoN::Deparse->new;
    my $out = $data ? $d->render($data) : undef;
    my $why = producer_stderr() . ($d->gap // q{});
    ok !defined $out, "$name: refuses";
    like $why, $want, "$name: names its cause";
}

my @cases = (
    [ q{my $s="aaa"; (my $c = $s) =~ tr/a/b/; print "$c $s\n";},
      'tr/// on a copy made in the same statement' ],
    [ q{my $s="aaa"; my $c; ($c = $s) =~ tr/a/b/; print "$c $s\n";},
      'tr/// on a copy into an existing lexical' ],
    [ q{my $s="abca"; my $n = ((my $c = $s) =~ tr/a/z/); print "$n $c\n";},
      'the count of tr/// on a copy' ],
    [ q{sub f { (my $c = shift) =~ tr/a-z/A-Z/; return $c } print f("hi"), f("yo"), "\n";},
      'tr/// on a copy in a sub' ],
    [ q{my @o; for my $w (qw(ab ba)) { (my $c = $w) =~ tr/a/x/; push @o, $c } print "@o\n";},
      'tr/// on a copy in a loop' ],
    [ q{my $x="aaa"; my $t="q"; $t .= ($x =~ tr/a/Z/r); print "$t $x\n";},
      'tr///r appended to a string' ],
    [ q{our $x="aaa"; $x =~ tr/a/b/; print "$x\n";},
      'tr/// on a package scalar' ],
    [ q{my @a=("aaa","c"); $a[0] =~ tr/a/b/; print "@a\n";},
      'tr/// on an array element' ],
    [ q{my %h=(k=>"aaa"); $h{k} =~ tr/a/b/; print "$h{k}\n";},
      'tr/// on a hash element' ],
    [ q{my $v="aaa"; my $r=\$v; $$r =~ tr/a/b/; print "$v\n";},
      'tr/// through a scalar reference' ],
    [ q{$_="aaa"; tr/a/b/; print "$_\n";},
      'tr/// on $_' ],
    [ q{my @a=("abca"); for my $i (1,2) { my $n = ($a[0] =~ tr/a-c/b-d/); print "$n @a\n" }},
      q{the count of tr/// on an element, in a loop} ],
    [ q{my @a=("aa","ab"); for (@a) { tr/a/c/ } print "@a\n";},
      q{tr/// on the aliased $_ of a loop} ],
    [ q{sub f { my $s = shift; return $s =~ tr/a/z/r } print f("aba"), "\n";},
      q{tr///r on a lexical, returned from a sub} ],
    [ q{my $x="abc"; print $x =~ tr/a-c//, "\n";},
      q{the count of tr/// in a list} ],
);

round_trips(@$_) for @cases;

refuses(q{our $g; my $s="aaa"; ($g = $s) =~ tr/a/b/; print "$g\n";},
    qr{GAP: tr/// on a copy into anything but a lexical not yet lowered},
    'tr/// on a copy into a package scalar');

done_testing;
