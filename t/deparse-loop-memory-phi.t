# ABOUTME: A loop's memory Phi carries the chain, not a value, so it gets no variable.
# ABOUTME: Declaring one asks for a MemStart as an expression, which has no spelling.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
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

# A LOOP CARRIES ITS MEMORY CHAIN IN A Phi, and that Phi is not a value.
# Measured on comp/retainedlines.t, three nested loops each with one:
#
#     13 MemStart
#     14 Phi in=[13, 14] region=4     region 4 is a Loop
#     15 Phi in=[14, 15] region=7
#     16 Phi in=[15, 16] region=10
#
# The second input is the Phi ITSELF -- correct SSA for a back edge, since at
# the header memory is either the entry value or what the body left.
#
# _emit_loop declares a variable per loop-carried Phi, which is right for a
# VALUE and wrong here: it asked for a MemStart as an expression, and a
# MemStart has no spelling. _join_phis already skips memory Phis at a branch
# join; a loop header needs the same rule.
#
# THE STORE MUST STILL BE OBSERVED. A loop whose body writes and whose later
# read sees the old value is the defect the memory chain exists to prevent, so
# the check is the VALUE after the loop, not that something rendered.
subtest 'a loop that writes an aggregate' => sub {
    round_trips(<<'SRC', 'a store in a loop body is observed after it');
my %seen;
my $i = 0;
while ($i < 3) { $seen{$i} = $i * 2; $i = $i + 1 }
my @k = sort keys %seen;
print "n=", scalar(@k), " last=", $seen{2}, "\n";
SRC
};

# NESTED LOOPS, which is comp/retainedlines.t's actual shape -- one memory Phi
# per header, each naming the one outside it. Asserted against the corpus file
# rather than a reproduction, because nested loops are a separate PRODUCER gap
# ("enterloop inside a loop body not yet lowered") and a synthetic case would
# never reach the emitter at all.
subtest 'the corpus shape: three stacked memory Phis' => sub {
    my $path = '/home/perigrin/dev/perl5/t/comp/retainedlines.t';
    skip_all 'perl source tree not available' unless -e $path;

    my $j = qx($^X -Ilib -MO=SoN,json,package=main $path 2>/dev/null);
    my $data = eval { JSON::PP->new->decode($j) } or do {
        fail 'it translates'; return;
    };
    my $g = $data->{methods}{'main::check_retained_lines'};
    ok $g, 'the method with the nested loops is present' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my @mem = grep {
        my $p = $_;
        ($p->{op} // '') eq 'Phi'
            && ((($by{ ($p->{fields} // {})->{region} // -1 }{op}) // '') eq 'Loop')
            && ((($by{ ($p->{inputs} // [])->[0] // -1 }{op}) // '') eq 'MemStart'
                || ($p->{inputs} // [])->[1] == $p->{id})
    } $g->{nodes}->@*;
    ok scalar(@mem) >= 1, 'it has a loop-carried memory Phi' or return;

    # THE SECOND INPUT IS THE PHI ITSELF -- correct SSA for a back edge, and
    # the shape that made this look like a value worth naming.
    my ($self_ref) = grep { (($_->{inputs} // [])->[1] // -1) == $_->{id} } @mem;
    ok $self_ref, 'whose second input is itself';

    # THE MemStart REFUSAL IS GONE. This method also holds a `ListAppend`
    # (a map/grep accumulator), which is a separate node with no rule yet --
    # so the assertion is that the memory Phi is no longer what stops it,
    # rather than that the whole method renders.
    my $d = SoN::Deparse->new;
    my $out = $d->render({ methods => { 'main::__PROGRAM__' => $g } });
    my $why = defined $out ? '' : ($d->gap // '');
    unlike $why, qr/MemStart/,
        'and no longer refuses on a MemStart as a value';
};

# A VALUE Phi MUST STILL GET ITS VARIABLE -- that is what makes a loop-carried
# counter work, and a fix that skipped every Phi would break it.
subtest 'a value Phi still becomes a variable' => sub {
    round_trips(<<'SRC', 'a counter and an accumulator');
my $i = 0;
my $sum = 0;
while ($i < 4) { $sum = $sum + $i; $i = $i + 1 }
print "i=$i sum=$sum\n";
SRC
};

done_testing;
