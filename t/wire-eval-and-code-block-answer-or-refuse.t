# ABOUTME: An eval of a constant string, or a regex code block, gives perl's answer
# ABOUTME: through the graph (Deparse), or B::SoN refuses it by name -- never a wrong graph.
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

sub produce ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    my $err = do { local (@ARGV, $/) = ("$dir/err"); <> } // '';
    return (scalar(eval { JSON::PP->new->decode($j) }), $err);
}

# Each found by review (2026-11-04) as a graph that meant something else.
for my $case (
    [ q{{ my $x = 10; sub g { return $x } } my $x = 1; eval '$x = 2'; print g(), " $x\n";}, 'an eval naming a name the file declares twice' ],
    [ q{{ my $x = 10; sub g { return $x } } my $x = 1; my $s = "a"; $s =~ /a(?{ $x = 2 })/; print g(), " $x\n";}, 'a code block naming a name the file declares twice' ],
    [ q{my $x = 1; our $x = 5; my $r = eval '$x + 0'; print "$r\n";}, 'an eval where an our masks a my' ],
    [ q{package Foo; our $p = 1; package main; eval '$p = 2'; print "$Foo::p ", ($main::p // 'u'), "\n";}, 'an eval naming an our of another package' ],
    [ q{use strict; my $x = 1; my $r = eval '$y = 5; 7'; print defined $r ? "r=$r" : "undef", " err=", ($@ ? "set" : "empty"), "\n";}, 'an eval under strict' ],
    [ q{my $n = 0; my $s = "a"; $s =~ /a(?{ while ($n < 4) { $n = $n + 1 } })/; print "$n\n";}, 'a loop in a code block' ],
    [ q{my $x = 1; my $r = eval 'BEGIN { print "begin\n" } $x + 1'; print "$r\n";}, 'a BEGIN in an eval string' ],
    [ q|my $x = 1; my $r = eval '1 }; sub { $x = 5'; print defined $r ? "def" : "undef", " $x\n";|, 'an eval string whose braces escape' ],
    [ q{my $s = "ab"; my $r = eval 'substr($s, 5, 1, "x"); 1'; print defined $r ? "def" : "undef", " $s\n";}, 'an eval whose substr can die' ],
    [ q{my @a = (1); eval q{ $a[-5] = 1 }; print "after [", ($@ ? "set" : ""), "]\n";}, 'an eval whose element store can die' ],
    [ q{my $x = 1; @ARGV = (5, 6); my $r = eval 'shift'; print "$r @ARGV\n";}, 'a bare shift in an eval' ],
    [ q{my $x = 1; $@ = "old"; my $r = eval 'length($@)'; print "$r\n";}, '$@ is cleared as the eval starts' ],
    [ q{my $x = 1; my $r = eval '__FILE__'; print "$r\n";}, '__FILE__ in an eval' ],
    [ q{my $x = 1; my $r = eval '__LINE__'; print "$r\n";}, '__LINE__ in an eval' ],
    [ q{use integer; my $x = 7; my $r = eval '$x * 1.5'; print "$r\n";}, 'an eval under use integer' ],
) {
    my ($src, $name) = @$case;
    my $want = run_perl($src);
    my ($data, $err) = produce($src);
    # A CODE BLOCK'S BODY is not what Deparse renders (it re-renders the
    # pattern text): a loop in one must be refused, not judged by Deparse.
    if ($name eq 'a loop in a code block') { like($err, qr/GAP:/, "$name: refused by name"); next }
    if (!$data || !$data->{methods}{'main::__PROGRAM__'}) {
        like($err, qr/GAP:/, "$name: refused by name");
        next;
    }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    if (!defined $out) { pass("$name: Deparse refuses (" . (($d->gap // '') =~ s/\n.*//sr) . ")"); next }
    is(run_perl($out), $want, "$name: perl's answer") or diag "--- emitted ---\n$out";
}

done_testing;
