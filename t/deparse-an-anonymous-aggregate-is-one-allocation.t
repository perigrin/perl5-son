# ABOUTME: An anonymous `{}` / `[]` is ONE allocation, pinned where it runs: every
# ABOUTME: name that holds it names the same aggregate, and a loop makes a new one each pass.

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

# ONE CONSTRUCTOR, TWO READERS, WAS TWO AGGREGATES. The literal had no place
# on the chain, so each read rendered it afresh: perl 1, emitted 0.
round_trips(<<'SRC', 'an empty array ref shared by two names');
my $r = []; my $s = $r; push @$s, 1; print scalar(@$r), "\n";
SRC

round_trips(<<'SRC', 'an empty hash ref shared by two names');
my $r = {}; my $s = $r; $s->{k} = 7; print $r->{k}, "\n";
SRC

round_trips(<<'SRC', 'a filled array ref shared by two names');
my $r = [1, 2]; my $s = $r; push @$s, 3; print "@$r\n";
SRC

round_trips(<<'SRC', 'a filled hash ref shared by two names');
my $r = {a => 1}; my $s = $r; $s->{b} = 2; print join(",", map { "$_=$r->{$_}" } sort keys %$r), "\n";
SRC

round_trips(<<'SRC', 'identity: two names, one address');
my $r = {}; my $s = $r; print $r == $s ? "same" : "diff", "\n";
SRC

round_trips(<<'SRC', 'a constructor in a loop body is a new one each pass');
my $o = ""; for my $i (1 .. 3) { my $r = []; push @$r, $i; $o .= scalar(@$r) } print "$o\n";
SRC

round_trips(<<'SRC', 'a constructor read once, inline');
print scalar(@{[1, 2, 3]}), "\n";
SRC

round_trips(<<'SRC', 'a constructor returned from a sub');
sub mk { return { n => $_[0] } } my $a = mk(1); my $b = $a; $b->{n} = 5; print $a->{n}, "\n";
SRC

# A SHARED AGGREGATE HOLDING CONSTRUCTORS is declared once, above the subs;
# its initialiser follows the pinned constructors it reads, and must assign
# rather than declare again -- `my %R` there masked the one the sub sees
# (chalk's KeywordTable.pm).
round_trips(<<'SRC', 'a file lexical shared with a sub, holding constructors');
my %R = (a => [1, 2], b => [3]); sub rule { return $R{$_[0]} } print rule("a")->[1], rule("b")->[0], "\n";
SRC

# A PINNED ALLOCATION IN A SHORT-CIRCUIT ARM moves the arm's control, so
# the arm needs its own branch -- without one the control before the
# operator had two successors, and `$x // []` (everywhere in chalk's lib/)
# refused.
round_trips(<<'SRC', 'a defined-or defaulting to an allocation');
sub f { my $l = $_[0] // []; push @$l, 9; return scalar(@$l) } print f([1, 2]), f(undef), "\n";
SRC

round_trips(<<'SRC', 'an or defaulting to an allocation');
sub f { my $h = $_[0] || {}; $h->{z} = 1; return scalar(%$h) } print f({a => 1}), f(0), "\n";
SRC

round_trips(<<'SRC', 'an and yielding an allocation');
sub f { my $r = $_[0] && [$_[0]]; return ref($r) ? $r->[0] : "none" } print f(5), f(0), "\n";
SRC

round_trips(<<'SRC', 'a ternary with an allocation in one arm');
sub f { return $_[0] ? 2 : [] } print f(1), ref(f(0)), "\n";
SRC

round_trips(<<'SRC', 'a ternary with an allocation in each arm');
sub f { my $r = $_[0] ? [1] : {}; return ref($r) } print f(1), f(0), "\n";
SRC

done_testing;
