# ABOUTME: A sub of many guarded early returns -- a dispatch -- renders in time:
# ABOUTME: asking whether a merge lies under an arm does not re-walk every path.

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

# EACH MERGE WALKED EVERY PREDECESSOR AFRESH, so a run of guarded returns
# doubled the walk at each one: chalk's LLVM::Context::lower_value, a hundred
# `if (...) { return ... }`, never finished rendering.
my $src = "sub f { my (\$x, \$c) = \@_; my \$v = 0;\n"
    . join('', map { "  if (\$x eq \"k$_\") { \$v = $_ if \$c; return \"r\$v\" }\n" } 1 .. 40)
    . "  return \"z\$v\" }\nprint f(\"k3\", 1), f(\"q\"), \"\\n\";\n";
my $ok = eval {
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm 30;
    round_trips($src, 'forty guarded returns');
    alarm 0;
    1;
};
alarm 0;
ok $ok, 'renders within 30 seconds' or diag $@;

done_testing;
