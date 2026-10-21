# ABOUTME: A while whose condition reads an element -- a hash walk up a parent chain,
# ABOUTME: a queue drained by key -- reads it afresh each pass, after the body's stores.

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

# A CONDITION THAT READS MEMORY was refused: its read had no header memory
# Phi to go through. chalk's TypeLibrary::_ancestors climbs %PARENT so.
round_trips(<<'SRC', 'a parent chain climbed by a hash read in the condition');
my %PARENT = (a => 'b', b => 'c', c => 'd');
sub ancestors { my ($t) = @_; my @chain = ($t); my $cur = $t; while (my $next = $PARENT{$cur}) { push @chain, $next; $cur = $next } return @chain }
print join(",", ancestors('a')), " ", join(",", ancestors('c')), "\n";
SRC
# ONE THE BODY STORES is lowered, and the renderer refuses it: the read is
# at the top of each pass, and it bound it inside the body, after the test
# that reads it -- `$eff23` used before its `my`.
{
    my $data = graph_of(<<'SRC');
my %h = (n => 3); my $s = "";
while ($h{n}) { $s .= $h{n}; $h{n}-- }
print "$s $h{n}\n";
SRC
    unlike producer_stderr(), qr/B::SoN/, 'a condition read of an element the body stores: the producer says nothing';
    my $d = SoN::Deparse->new;
    ok !defined $d->render($data // {}), '... and the renderer refuses';
    like $d->gap // '', qr/GAP: a loop condition reads a value its body binds/, '... naming its cause';
}

round_trips(<<'SRC', 'an array element condition, the index advanced in the body');
my @a = (5, 4, 0, 9); my $i = 0; my $t = 0;
while ($a[$i]) { $t += $a[$i]; $i++ }
print "$t $i\n";
SRC

round_trips(<<'SRC', 'a statement-modifier while over an element');
my @a = (1, 2, 3, 0, 5); my $i = 0; $i = $i + 1 while $a[$i]; print "$i\n";
SRC
round_trips(<<'SRC', 'a hash element condition whose key the body clears');
my %h = (a => 1); my $k = "a"; my $n = 0; while ($h{$k}) { $k = ""; $n++ } print "$n|$k|\n";
SRC

# A `my` IN THE CONDITION WRAPS THE BODY IN enter/leave, and the walker took
# that block for a do-block: its statements never counted, so `if (C) {
# return }` in it fell to the loop-condition handler -- "nested and/or
# inside a loop body". chalk's TypeLibrary::is_subtype.
round_trips(<<'SRC', 'a guarded return in the body of a while that declares');
my %PARENT = (a => 'b', b => 'c', c => 'd'); my %cache;
sub is_sub { my ($child, $parent) = @_; my $current = $child;
  while (my $next = $PARENT{$current}) { if ($next eq $parent) { $cache{"$child$parent"} = 1; return 1 } $current = $next }
  $cache{"$child$parent"} = 0; return 0 }
print is_sub('a', 'c'), is_sub('a', 'x'), is_sub('c', 'd'), " ", join(",", map { "$_=$cache{$_}" } sort keys %cache), "\n";
SRC

# A `my` IN THE CONDITION, DEMOTED -- passed to a call, so it lives in
# memory -- is STORED there each pass, and the store hung off the
# condition's shift, past the effects the header emits: the body read a
# variable nothing assigned (`<><>` for `<1><2>`, at base too). chalk's
# LR0DFA::_compute_prediction_closure passes it to a method.
round_trips(<<'SRC', 'a declared condition variable passed to a call');
sub g { "<$_[0]>" } sub f { my @w = (1, 2); my $s = ""; while (my $n = shift @w) { $s .= g($n) } $s } print f(), "\n";
SRC
round_trips(<<'SRC', '... passed to a method');
package O { sub m { "<$_[1]>" } } sub f { my @w = (1, 2); my $s = ""; while (my $n = shift @w) { $s .= O->m($n) } $s } print f(), "\n";
SRC

done_testing;
