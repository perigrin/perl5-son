# ABOUTME: On wire v2 a node's memory version (mem_in) is listed before it, as its inputs
# ABOUTME: are: chalk's loader refuses a forward reference other than a loop's back edge (L8).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# docs/plans/2026-11-20-wire-v2.md, section 8.3, L8: the only forward
# references in a graph are a loop Phi's back input and Loop.inputs[1]. chalk
# reads a node's memory where it reads the node, so a mem_in naming a node
# later in the list is refused (a node on no control chain), or deferred. The
# writer's topological order takes mem_in as a predecessor; this holds it,
# over the shapes where the memory named is not otherwise before the node: a
# merge's memory Phi read after the merge, a loop's, a cell, a sub's exits.
my $dir = tempdir( CLEANUP => 1 );
my @src = (
    q{my %h; if ($ARGV[0]) { $h{a} = 1 } else { $h{b} = 2 } print join(",", sort keys %h), "\n";},
    q{my @a = (1); for my $i (1 .. 3) { push @a, $i } print scalar(@a), "\n";},
    q{my $n = 1; my $f = sub { $n += 2 }; $f->(); if ($n) { $f->() } print "$n\n";},
    q{our $g; sub f { if ($_[0]) { $g = 1; return 2 } $g = 3; return 4 } print f(1), f(0), "$g\n";},
    q{my %h = (a => 1); my $r = eval { die "x\n" if $h{a}; 1 }; $h{b} = 2; print $r // "u", $@, "\n";},
    q{my @q = (3, 2, 1); while (my $x = shift @q) { $q[0]++ if @q } print "@q\n";},
);
my $bad = 0;
for my $i ( 0 .. $#src ) {
    my $f = "$dir/c$i.pl";
    open my $o, '>', $f or die $!;
    print $o $src[$i];
    close $o;
    my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json,wire=2,not_package=SoN $f 2>/dev/null) );
    for my $g ( sort keys $w->{methods}->%* ) {
        my $nodes = $w->{methods}{$g}{nodes};
        for my $n (@$nodes) {
            my $f   = $n->{fields} // {};
            my $rgn = defined $f->{region} ? $nodes->[ $f->{region} ]{op} // '' : '';
            my @in  = map { ref $_ ? @$_ : $_ } ( $n->{inputs} // [] )->@*;
            my @ref = (
                ( map { [ "input $_", $in[$_] ] } grep { !( $_ == 1 && ( $n->{op} eq 'Loop' || ( $n->{op} eq 'Phi' && $rgn eq 'Loop' ) ) ) } 0 .. $#in ),
                ( map { [ $_, $n->{$_} ] } grep { defined $n->{$_} } qw(control_in mem_in head) ),
                ( $n->{op} eq 'Phi' && defined $f->{region} ? [ region => $f->{region} ] : () ),
            );
            for my $r ( grep { $_->[1] >= $n->{id} } @ref ) {
                $bad++;
                diag "case $i, $g: $n->{op} #$n->{id} names #$r->[1] ($nodes->[ $r->[1] ]{op}) by $r->[0]";
            }
        }
    }
}
is $bad, 0, 'no forward reference but a loop back edge';

done_testing;
