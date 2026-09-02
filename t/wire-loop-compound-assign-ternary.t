# ABOUTME: A compound assignment whose RHS is a ternary still writes back and gets a loop Phi.
# ABOUTME: `$s += ($c ? 10 : 1)` in a while loop -- the accumulator, not just the counter.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub nodes_of ($src, $name) {
    my $wire = wire_for($src, $name);
    return ($wire->{methods}{'main::__PROGRAM__'}{nodes} // []);
}

# THE ACCUMULATOR MUST CROSS THE BACK EDGE. A while loop mutating two variables
# needs two header Phis: the counter AND the accumulator. With only the
# counter's, `$s` reads its PRE-LOOP binding forever and the emitted graph
# means 0 -- a SILENT WRONG ANSWER, not a refusal. perl prints 12.
#
# Found by chalk's corpus gate (control-flow.md T3): perl 12, lli 0.
my $T3 = 'my $i=0; my $s=0; while ($i<3) { $s += ($i>1 ? 10 : 1); $i++ } say($s);';

subtest 'the accumulator gets a loop Phi, not just the counter' => sub {
    my $nodes = nodes_of($T3, 't3');
    my @phis = grep { $_->{op} eq 'Phi' } $nodes->@*;
    is scalar(@phis), 2,
        'two loop-carried variables means two header Phis';
};

# THE ORPHAN. The `$s += ...` Add fed NOTHING on the wire: it was computed and
# discarded, because the write-back that would consume it was never emitted.
# A node consumed by nothing whose operator has no effect is dead code the
# producer built on purpose, which is the shape of a dropped assignment.
subtest 'no arithmetic node is left unconsumed' => sub {
    my $nodes = nodes_of($T3, 't3_orphan');
    my %used;
    for my $n ($nodes->@*) { $used{$_}++ for ($n->{inputs} // [])->@* }
    my @orphans = grep { !$used{$_->{id}} && $_->{op} eq 'Add' } $nodes->@*;
    is scalar(@orphans), 0,
        'the accumulator Add is consumed, not computed and dropped'
        or diag explain [ map { "$_->{id} $_->{op}" } @orphans ];
};

# WHAT IS PRINTED MUST NOT BE THE PRE-LOOP CONSTANT. The clearest statement of
# the miscompile: Print read `Coerce <- Constant(0)`, the initial `my $s = 0`,
# so the graph MEANT zero. Its argument must trace to the loop, not to the
# initialiser.
subtest 'the printed value comes from the loop, not the initialiser' => sub {
    my $nodes = nodes_of($T3, 't3_print');
    my %byid = map { $_->{id} => $_ } $nodes->@*;
    my ($print) = grep { $_->{op} eq 'Print' } $nodes->@*;
    ok defined $print, 'the print exists' or return;

    # Walk back from Print's argument; a correct graph reaches a Phi or an Add.
    my (@queue, %seen) = (($print->{inputs} // [])->@*);
    my $reaches_loop = 0;
    while (my $id = shift @queue) {
        next if $seen{$id}++;
        my $n = $byid{$id} or next;
        $reaches_loop = 1, last if $n->{op} eq 'Phi' || $n->{op} eq 'Add';
        push @queue, ($n->{inputs} // [])->@*;
    }
    ok $reaches_loop,
        'the printed value depends on the loop body, not only on the initialiser';
};

# THE SAME SHAPE WITHOUT A TERNARY ALREADY WORKED. Asserted so a fix cannot be
# written that only special-cases the ternary and leaves the general rule alone,
# and so a regression here is attributed correctly.
subtest 'the plain compound assignment still works' => sub {
    my $nodes = nodes_of('my $i=0; my $s=0; while ($i<3) { $s += 1; $i++ } say($s);', 'plain');
    my @phis = grep { $_->{op} eq 'Phi' } $nodes->@*;
    is scalar(@phis), 2, 'counter and accumulator both carried';
};

# A DIFFERENT OPERATOR, same defect: this is the `OP=` family, not `+=` alone.
subtest 'a multiplying accumulator is carried too' => sub {
    my $nodes = nodes_of('my $i=0; my $s=1; while ($i<3) { $s *= ($i>1 ? 2 : 3); $i++ } say($s);', 'mul');
    my @phis = grep { $_->{op} eq 'Phi' } $nodes->@*;
    is scalar(@phis), 2, '*= carries its accumulator as well';
};

done_testing;
