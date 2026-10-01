# ABOUTME: `$x //= E` (and ||=, &&=) into a shared or referenced lexical: E runs only
# ABOUTME: when the test fails, and the store goes into the slot every reader sees.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
    }
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

# THE MEMO IDIOM REFUSED: `$CACHE //= make()` over a file lexical a method
# closes over -- "`//=` into a referenced lexical", 7 graphs in chalk's lib/
# (Semiring::Boolean's zero/one among them).
round_trips(<<'SRC', 'a memoised file lexical, read through a sub');
my $C; my $n = 0;
sub make { $n++; return [7] }
sub get { $C //= make(); return $C }
print get()->[0], get()->[0], " made $n\n";
SRC

round_trips(<<'SRC', 'a memoised file lexical in a class method');
use v5.42; use experimental 'class';
my $Z; my $built = 0;
class K { method zero { $Z //= do { $built++; [0] }; return $Z } }
my $k = K->new; $k->zero; $k->zero; print scalar(@{ $k->zero }), " built $built\n";
SRC

round_trips(<<'SRC', 'or-assign and and-assign into a referenced lexical');
my $x = 0; my $r = \$x; $x ||= 5; my $y = 3; my $s = \$y; $y &&= 9; print "$x $$r $y $$s\n";
SRC

round_trips(<<'SRC', 'the right side runs only when needed');
my $calls = 0; sub v { $calls++; 4 } my $x = 1; my $r = \$x; $x //= v(); $x = undef; $x //= v(); print "$x $calls\n";
SRC

# A STORE INTO A SHARED LEXICAL IN A BRANCH ARM VANISHED, whatever the
# operator: the arm walkers did not know the slot was demoted, so the store
# was an SSA rebind nothing outside the arm could see. perl 1, emitted 0.
round_trips(<<'SRC', 'an increment of a shared lexical in an if');
my $b = 0; sub f { my $c = shift; if ($c) { $b++ } } f(1); f(0); print "$b\n";
SRC

round_trips(<<'SRC', 'an assignment to a shared lexical in an else');
my $b = "x"; sub f { if ($_[0]) { return 1 } else { $b = "y" } } f(0); print "$b\n";
SRC

round_trips(<<'SRC', 'an increment in a ternary arm');
my $b = 0; sub f { my $v = $_[0] ? do { $b++; 1 } : 2; $v } f(1); f(0); print "$b\n";
SRC

round_trips(<<'SRC', 'an increment of a referenced lexical in a loop body');
my $n = 0; my $r = \$n; for my $i (1 .. 4) { $n++ if $i % 2 } print "$n $$r\n";
SRC

done_testing;
