# ABOUTME: SoN::Render::WireYAML writes the wire as compact flow YAML; parsed back
# ABOUTME: with YAML::PP it must be the same graph, down to each value's type.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use YAML::PP;

use SoN::Render::WireYAML;

my $dir = tempdir(CLEANUP => 1);
my $J = JSON::PP->new->canonical;

sub wire_of ($src) {
    my $f = "$dir/w." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return $J->decode(scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err));
}

# The wire graph rebuilt from the parsed YAML: a node's list INDEX is its id,
# and a Region's head rides in its fields map.
sub from_yaml ($g) {
    my @nodes;
    my $nodes = $g->{nodes} // [];
    for my $id (0 .. $#$nodes) {
        my ($op, $f, $in, $ctl, $stamp) = $nodes->[$id]->@*;
        my %f = %{ $f // {} };
        my $head = delete $f{head};
        push @nodes, {
            id => $id, op => $op, inputs => $in // [],
            (%f            ? (fields => \%f)         : ()),
            (defined $ctl  ? (control_in => $ctl)    : ()),
            (defined $stamp ? (stamp => $stamp)      : ()),
            (defined $head ? (head => $head)         : ()),
        };
    }
    return { start => $g->{start}, returns => $g->{returns}, nodes => \@nodes };
}

sub normal ($g) {
    return { start => $g->{start}, returns => $g->{returns},
             nodes => [ map { my %n = %$_; delete $n{fields} unless %{ $n{fields} // {} };
                              $n{inputs} //= []; \%n }
                        sort { $a->{id} <=> $b->{id} } $g->{nodes}->@* ] };
}

# AWKWARD VALUES ON PURPOSE: a newline, sigils that are YAML indicators (`@`,
# `%`, `&`), words YAML 1.1 reads as booleans or null, strings that look like
# numbers, an empty string, undef.
my @programs = (
    <<'SRC',
sub sign { my $n = shift; return "neg" if $n < 0; return "pos" }
print sign(-1), sign(1), "\n";
SRC
    <<'SRC',
use strict;
my @a = ("yes", "no", "null", "~", "0", "1.5", "", "a: b", "#x", "on");
my %h = (k => "v");
my $r = \@a;
print "@a $h{k} ", scalar(@$r), "\n";
my $u; print defined($u) ? "d" : "u", "\n";
SRC
);

for my $src (@programs) {
    my $wire = wire_of($src);
    my $yaml = SoN::Render::WireYAML::render($wire);
    my $back = eval { YAML::PP->new(schema => ['Core'])->load_string($yaml) };
    ok $back, 'the YAML parses' or do { diag $@; diag $yaml; next };

    my %want = map { ($_ => normal($wire->{methods}{$_})) } keys $wire->{methods}->%*;
    my $i = 0;
    $want{ ($_->{phase} // 'PHASE') . ' ' . ++$i } = normal($_)
        for ($wire->{phase_blocks} // [])->@*;
    my %got = map { ($_ => from_yaml($back->{$_})) } keys %$back;

    is [sort keys %got], [sort keys %want], 'one entry per graph';
    for my $g (sort keys %want) {
        is $J->encode($got{$g} // {}), $J->encode($want{$g}),
            "$g: the same graph, types included"
            or diag $yaml;
    }

    # THE ID IS THE INDEX, and the comment says it for a reader counting.
    for my $g (sort keys %want) {
        my $n = scalar $want{$g}{nodes}->@*;
        my @c = $yaml =~ /^  \[.*# (\d+)$/mg;
        ok scalar(grep { $_ == $n - 1 } @c), "$g: its last node is labelled # " . ($n - 1);
    }
    is SoN::Render::WireYAML::render($wire), $yaml, 'rendering is deterministic';
}

done_testing;
