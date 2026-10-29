# ABOUTME: a sub's exit that dies never yields a value, so the `()` it carries
# ABOUTME: must not make the merged return a list: a scalar caller gets the value, not a count.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# chalk's Context::_lower_constant: if/elsif arms return a scalar, the else
# dies. The die's exit carried an empty list into the exit merge, so the
# merge was an array and a scalar caller got its count: perl "Aa Bb 1",
# emitted "1 1 1" (lli: `extractvalue %Str 1, 0`).
for my $src (
    q{sub k { my $r = shift; if ($r eq 'a') { return "A$r" } elsif ($r eq 'b') { return "B$r" } else { die "no $r\n" } }
      my $x = k('a'); my $y = k('b'); my @z = k('a');
      print "$x $y ", scalar(@z), "\n";},
    q{sub k { my $r = shift; return "A$r" if $r eq 'a'; die "no $r\n" }
      my $x = k('a'); my @z = k('a'); print "$x ", scalar(@z), "\n";},
    # chalk's Context::lower_value: the else ends `if (C && D) { die } die`,
    # so the exit's control is a Region of two Unwinds -- every way in dies.
    q{my %C = (q => 'cq');
      sub k { my $r = shift; my $s = shift;
        return $C{$r} if exists $C{$r};
        if ($r eq 'a') { return "A$r" } elsif ($r eq 'b') { return "B$r" }
        elsif ($r eq 'n') { die "n\n" }
        else { if (defined $s && $s eq 'S') { die "s\n" } die "no $r\n" } }
      my $x = k('a'); my $y = k('b'); my $w = k('q'); my @z = k('a');
      print "$x $y $w ", scalar(@z), "\n";},
) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    ok($data, "translates") or next;
    my $d    = SoN::Deparse->new;
    my $perl = $d->render($data);
    if (!defined $perl) { like($d->gap, qr/GAP/, "refused by name: $src"); next }
    is(run_perl($perl), $want, "deparses to what perl prints: $want")
        or diag $perl;
}

done_testing;
