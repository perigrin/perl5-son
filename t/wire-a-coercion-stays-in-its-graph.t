# ABOUTME: A coercion the post-pass inserts belongs to the graph it was inserted into: two
# ABOUTME: graphs whose node ids coincide must not share one Coerce, or one sub reads the other's nodes.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# The emitted program in the defect recursed without end and grew past 15GB:
# cap its memory as well as its time.
sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(ulimit -v 1000000; /usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# THE FACT, not the emission: f's own graph holds its `shift` and no call to f.
# Node ids are per-graph (`Call#3` in main and `Call#3` in f), so the EntryDef
# for `$"` read after each had one content hash; a factory shared across graphs
# handed f main's Coerce, and with it main's Call and Constant.
sub keeps_its_own_nodes ($src, $name) {
    my $data = graph_of($src) or return fail "$name: translates";
    my $nodes = $data->{methods}{'main::f'}{nodes} // [];
    my @self = grep { ($_->{fields}{name} // '') eq 'main::f' } @$nodes;
    my @shift = grep { ($_->{fields}{name} // '') eq 'shift' } @$nodes;
    is scalar @self, 0, "$name: f's graph has no call to f";
    is scalar @shift, 1, "$name: f's graph keeps its shift";
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src) or return fail "$name: translates";
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
}

my @cases = (
    [ q{sub f { my $k=shift; my @o=(1,$k); return "L@o" } my @x=f(3); print "@x\n";},
      'straight-line' ],
    [ q{sub f { my $k=shift; my @o=(1,2); return "L@o" if $k; return 0 } my @x=f(3); print "@x\n";},
      'a guarded return' ],
    [ q{sub f { my $k=shift; my @o; for my $i (1..5) { return @o if $i == $k; push @o, $i } return "L@o" } my @x=f(3); print "@x\n";},
      'a guarded return in a loop' ],
    [ q{sub f { my $k=shift; my @o; for my $i (1..5) { if ($i > 2) { return @o if $i == $k; } push @o, $i } return "L@o" } my @x=f(3); print "@x\n";},
      'a guarded return in a loop-body arm' ],
    [ q{sub f { my $k=shift; my @o; for my $i (1..5) { if ($i > 2) { last if $i > 4; return @o if $i == $k; } push @o, $i } return "L@o" } my @x=f(3); print "@x\n";},
      'a last and a guarded return in a loop-body arm' ],
);

for my $c (@cases) {
    subtest $c->[1] => sub {
        keeps_its_own_nodes(@$c);
        round_trips(@$c);
    };
}

done_testing;
