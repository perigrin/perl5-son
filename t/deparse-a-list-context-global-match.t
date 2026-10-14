# ABOUTME: A /g match in list context yields every match, so it is a list and not
# ABOUTME: the Boolean of a scalar /g match; one in the caller's context refuses.

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
# Bound as a scalar, the match kept its first hit: 1 for perl's (1, 2).
round_trips(q{my $s = "a1b2"; my @m = $s =~ /\d/g; print "@m\n";}, 'into an array');
round_trips(q{my $s = "a1b2"; print join(",", $s =~ /\d/g), "\n";}, 'as a join argument');
round_trips(q{my $s = "a1b2"; for my $d ($s =~ /\d/g) { print $d } print "\n";}, 'as a foreach list');
round_trips(q{my $s = "a1b2"; my @m = ($s =~ /(\w)(\d)/g); print "@m\n";}, 'with two groups');
round_trips(q{my $s = "a1b2"; my @m = $s =~ /(\d)/g; print "@m $1\n";}, 'and the last capture after it');
round_trips(q{my @l = ("a1b2", "c3"); for (@l) { my @m = /\d/g; print scalar(@m) } print "\n";},
    'on the topic in a loop');

# THE COUNT OF ONE: `() = LIST` in scalar context counts the list, and a match
# was counted as one value.
round_trips(q{my $s = "a1b2"; my $n = () = $s =~ /\d/g; print "$n $s\n";}, 'counted');
round_trips(q{$_ = "a1b2c3"; my $n = () = /\d/g; print "$n\n";}, 'counted on the topic');
round_trips(q{my $s = "a1b2"; my $n = () = ($s =~ /\d/g, 5); print "$n\n";}, 'counted with a value after it');
round_trips(q{my $s = "a1b2"; my $n = () = $s =~ /(\w)(\d)/; print "$n\n";}, 'a counted non-/g match');
round_trips(q{my $s = "a1b2"; my $n = () = $s =~ /\d/g; $s =~ s/(\d)/$1*2/ge; print "$n $s\n";},
    'counted, then a /ge on the same subject');

# The CALLER decides a returned match's context, and the graph cannot.
refuses(q{sub f { my $s = shift; return $s =~ /\d/g } my @r = f("a1b2"); print "@r\n";},
    qr/GAP: a \/g match in the caller's context/, 'returned from a sub');
refuses(q{sub f { $_[0] =~ /\d/g } my $n = () = f("a1b2"); print "$n\n";},
    qr/GAP: a \/g match in the caller's context/, 'as a sub\'s last statement');

done_testing;
