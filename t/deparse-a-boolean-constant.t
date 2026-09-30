# ABOUTME: A boolean Constant -- `true`, `false`, a folded `!!1` -- renders as perl's
# ABOUTME: own boolean, so it prints the same and is still a boolean.

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

# "no rule for a `boolean` Constant" refused 21 of chalk's lib/ modules
# whole -- `return true`, `my $ok = false` and the like.
round_trips(<<'SRC', 'true and false print as perl prints them');
use v5.42; my $t = true; my $f = false; print "[$t][$f]\n";
SRC

round_trips(<<'SRC', 'a boolean returned from a sub is tested');
use v5.42; sub yes { return true } sub no_ { return false }
print yes() ? "y" : "n", no_() ? "y" : "n", "\n";
SRC

# THE VALUE IS STILL A BOOLEAN. `1` and `""` would print the same and lose
# what builtin::is_bool reports.
round_trips(<<'SRC', 'it is still a boolean');
use v5.42; no warnings 'experimental::builtin';
my $t = true; my $f = false;
print builtin::is_bool($t) ? "b" : "-", builtin::is_bool($f) ? "b" : "-", "\n";
SRC

done_testing;
