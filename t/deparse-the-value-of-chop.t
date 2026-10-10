# ABOUTME: chop and chomp yield what they removed -- the character, or the count -- not the
# ABOUTME: trimmed string, in every context; an element subject still refuses by name.

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


my @cases = (
    [ q{my $k = "ab"; my $x = chop $k; print "$x\n";},
      'the value of chop is the removed character' ],
    [ q{my $k = "ab\n"; my $x = chomp $k; print "$x [$k]\n";},
      'the value of chomp is the count removed' ],
    [ q{my $k = "ab"; my $x = chomp $k; print "$x [$k]\n";},
      'chomp with nothing to remove counts zero' ],
    [ q{our $g = "xy\n"; my $n = chomp $g; print "$n [$g]\n";},
      'chomp of a package scalar' ],
    [ q{our $g = "xy\n"; sub f { my $n = chomp $g; print "$n [$g]\n" } f(); f();},
      q{chomp of a package scalar in a sub sees each call's value} ],
    [ q{our $g = "ab"; for my $i (1, 2) { my $x = chop $g; print "$x $g\n" }},
      'chop of a package scalar in a loop' ],
    [ q{$_ = "ab"; my $x = chop; print "$x $_\n";},
      'chop of the default $_' ],
    [ q{my $s = "ab"; print chop($s), " $s\n";},
      'chop read in list context' ],
    [ q{sub f { my $t = shift; return chop $t } print f("pq"), "\n";},
      'chop returned from a sub' ],
    [ q{my @r; for my $w (qw(ab cd)) { my $t = $w; push @r, chop $t } print "@r\n";},
      'chop in a loop' ],
    [ q{my ($p, $q) = ("a\n", "b\n"); my $n = chomp($p, $q); print "$n $p$q\n";},
      'a list chomp counts every argument' ],
    [ q{my ($p, $q) = ("ab", "cd"); my $n = chop($p, $q); print "$n $p $q\n";},
      'a list chop yields the last removed character' ],
);

round_trips(@$_) for @cases;

# AN ELEMENT HAS NO SLOT YET. The store back through a Subscript is not
# lowered, so the program is refused rather than emitted without its write.
my $g = graph_of(q{my @a = ("ab"); my $x = chop $a[0]; print "$x\n";});
like producer_stderr(),
    qr/GAP: a chomp\/chop whose subject is a `SoN::IR::Node::Subscript` has no slot/,
    'chop of an element refuses by name';

done_testing;
