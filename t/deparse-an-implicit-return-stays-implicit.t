# ABOUTME: A sub that returns by falling off its end is emitted that way -- its last
# ABOUTME: statement bare, not `return X` -- and one that said `return` keeps it.

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

sub round_trips ($src, $name, $spelled = undef, $not = undef) {
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
    like $out, $spelled, "$name: spelled as the source" if $spelled;
    unlike $out, $not, "$name: not spelled otherwise" if $not;
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# EVERY RETURN WAS SPELLED `return`. The same value either way, but chalk
# reads lib/ as source: `method operation() { 'Start' }` should end in a
# Constant statement, and it found a Return.
round_trips(<<'SRC', 'a constant fallen off the end', qr/^sub f\(\) \{\n7;\n\}/m);
use v5.42; sub f () { 7 } print f(), "\n";
SRC

round_trips(<<'SRC', 'an explicit return keeps its word', qr/^return 7;$/m);
use v5.42; sub f () { return 7 } print f(), "\n";
SRC

round_trips(<<'SRC', 'a method fallen off the end', qr/^method op\(\) \{\n"Start";\n\}/m);
use v5.42; use experimental 'class';
class P { method op() { 'Start' } } print P->new->op, "\n";
SRC

round_trips(<<'SRC', 'an array fallen off the end, in both contexts');
use v5.42; sub f () { my @a = (4, 5, 6); @a }
my @l = f(); my $s = f(); print "@l $s\n";
SRC

round_trips(<<'SRC', 'an if/else value fallen off the end');
use v5.42; sub f ($x) { if ($x) { 'a' } else { 'b' } } print f(1), f(0), "\n";
SRC

round_trips(<<'SRC', 'an early return beside a fallen-off end');
use v5.42; sub f ($x) { return 'e' if $x; 'f' } print f(1), f(0), "\n";
SRC

# A SUB THAT ENDS IN die RETURNS NOTHING -- the Return behind the Unwind is
# never reached, and its value was stack residue: `die(...); $ir;` after a
# signature parameter. chalk's Chalk::Target::generate is that shape, and
# perl-actions-tier-a.t counts its statements.
round_trips(<<'SRC', 'a method ending in die', qr/^die\("Subclass must implement generate\(\)\\n"\);\n\}/m);
use v5.42; use experimental 'class';
class T { method generate($ir) { die "Subclass must implement generate()\n" } }
print eval { T->new->generate(1); 1 } ? "ran\n" : $@;
SRC

done_testing;
