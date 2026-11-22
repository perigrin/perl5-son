# ABOUTME: A read through an element makes the element when it is not there (autovivification),
# ABOUTME: as perl does: `my $x = $h{a}{b}` leaves $h{a} a hash (audit 2026-11-22, W9).

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

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src) or return fail "$name: translates";
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) { my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s; fail "$name: renders"; diag $g; return }
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
}


round_trips(q{my %h; my $x = $h{a}{b}; print scalar(keys %h), "\n";}, 'a hash element read through');
round_trips(q{my @a; my $x = $a[1]{k}; print scalar(@a), "\n";}, 'an array element read through');
round_trips(q{my %h; print "y\n" if $h{a}{b}; print scalar(keys %h), "\n";}, 'read as a condition');
round_trips(q{sub cfg { my $c = shift; return $c->{opt}{verbose} ? 1 : 0 } my %c; cfg(\%c); print join(",", keys %c), "\n";}, 'through a reference, in a sub');
round_trips(q{my %h; my $v = $h{a}{b}{c}; print join(",", sort keys %h), ":", join(",", keys %{$h{a}}), "\n";}, 'three levels');
round_trips(q{my %h = (a => {b => 1}); my $x = $h{a}{b}; print "$x ", scalar(keys %h), "\n";}, 'one that is there');

done_testing;
