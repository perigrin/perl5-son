# ABOUTME: A signature parameter used as a variable -- `pos($input) = ...` -- is one
# ABOUTME: variable in the emission, not `$_[0]` in one place and a fresh `my` in another.

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

# PARAMETERS READ AS `$_[N]`, and a use of the parameter AS A VARIABLE --
# pos() as an lvalue -- named a `my $input` nothing assigned. So pos was set
# on a fresh undef while the match ran on $_[0]: chalk's
# Bootstrap::Terminal::match never advanced, and every grammar test that
# parses failed against the emitted lib/.
round_trips(<<'SRC', 'pos() set on a parameter, then a \\G match');
use v5.42;
sub match ($input, $position, $pattern) {
    pos($input) = $position;
    if ($input =~ /\G($pattern)/) { return $position + length($1) }
    return undef;
}
print match("aab", 1, "a+"), " ", (match("aab", 2, "a") // "undef"), "\n";
SRC

round_trips(<<'SRC', 'a parameter with a default, used as a variable');
use v5.42;
sub f ($s, $at = 0) { pos($s) = $at; $s =~ /\G(.)/; return $1 }
print f("xyz"), f("xyz", 2), "\n";
SRC

round_trips(<<'SRC', 'the caller\'s string keeps its own pos');
use v5.42;
sub m1 ($s) { pos($s) = 2; return pos($s) }
my $t = "hello"; pos($t) = 1; m1($t); print pos($t), "\n";
SRC

done_testing;
