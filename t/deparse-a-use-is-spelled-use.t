# ABOUTME: A `use Module LIST` / `no Module LIST` is emitted as the statement it was, not as
# ABOUTME: the BEGIN block perl lowers it to -- chalk reads lib/ source and looks for the `use`.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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

sub round_trips ($src, $name, $spelled = undef) {
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
    like $out, $spelled, "$name: spelled as a statement" if $spelled;
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# perl LOWERS `use X LIST` to `BEGIN { require X; X->import(LIST) }`, and the
# emission spelled that: `BEGIN { require("utf8.pm"); "utf8"->import() }`.
# Same program -- and chalk's perl-actions tests read lib/Chalk/IR/Node/
# Start.pm and look for its `use utf8` and `use experimental` statements.
round_trips(<<'SRC', 'use utf8', qr/^use utf8;$/m);
use utf8; my $s = "abc"; print length($s), "\n";
SRC

round_trips(<<'SRC', 'use with a constant list', qr/^use List::Util "sum", "max";$/m);
use List::Util qw(sum max); print sum(1, 2, 3), max(4, 5), "\n";
SRC

round_trips(<<'SRC', 'no with a constant list', qr/^no warnings "once";$/m);
no warnings 'once'; $main::x = 1; print "ok\n";
SRC

round_trips(<<'SRC', 'use with an empty list', qr/^use List::Util \(\);$/m);
use List::Util (); print List::Util::sum(1, 2), "\n";
SRC

round_trips(<<'SRC', 'use experimental in a class', qr/^use experimental "class";$/m);
use v5.42; use experimental 'class';
class C { method m { return 7 } } print C->new->m, "\n";
SRC

done_testing;
