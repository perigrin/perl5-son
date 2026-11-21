# ABOUTME: chalk's verifier counts per graph: the line format tools/wire-verify.pl
# ABOUTME: writes and t/data/wire-verify-chalk-graphs.tsv records, and their comparison.
package WireRatchet;
use v5.42.0;
use Exporter 'import';
our @EXPORT_OK = qw(parse_graph_lines graph_line compare_graphs);

# A line: SOURCE TAB @GRAPH TAB rule=n,rule=n (empty for a clean graph).

# graph_line($source, $graph, {rule => n}) -> the line, without its newline.
sub graph_line ( $source, $graph, $rules ) {
    return "$source\t\@$graph\t" . join ',', map {"$_=$rules->{$_}"} grep { $rules->{$_} } sort keys %$rules;
}

# parse_graph_lines(@lines) -> { source => { graph => { rule => n } } }; lines
# that are not graph lines are skipped.
sub parse_graph_lines (@lines) {
    my %g;
    for (@lines) {
        chomp( my $l = $_ );
        my ( $source, $graph, $rules ) = split /\t/, $l, 3;
        next unless defined $graph && $graph =~ s/^@//;
        $g{$source}{$graph} = { map { split /=/ } grep {length} split /,/, $rules // '' };
    }
    return \%g;
}

# compare_graphs($record, $got) -> { rose, fell, new, gone }: rose and fell are
# [source, graph, rule, was, now]; new is [source, graph, rules] (a graph the
# record does not name: printed, never a failure); gone is [source, graph].
# Only sources in $got are compared.
sub compare_graphs ( $want, $got ) {
    my %c = ( rose => [], fell => [], new => [], gone => [] );
    for my $s ( sort keys %$got ) {
        my ( $w, $g ) = ( $want->{$s} // {}, $got->{$s} );
        for my $graph ( sort keys %$g ) {
            if ( !exists $w->{$graph} ) { push $c{new}->@*, [ $s, $graph, $g->{$graph} ]; next }
            my %rules = ( $w->{$graph}->%*, $g->{$graph}->%* );
            for my $r ( sort keys %rules ) {
                my ( $was, $now ) = ( $w->{$graph}{$r} // 0, $g->{$graph}{$r} // 0 );
                push $c{rose}->@*, [ $s, $graph, $r, $was, $now ] if $now > $was;
                push $c{fell}->@*, [ $s, $graph, $r, $was, $now ] if $now < $was;
            }
        }
        push $c{gone}->@*, map { [ $s, $_ ] } grep { !exists $g->{$_} } sort keys %$w;
    }
    return \%c;
}

1;
