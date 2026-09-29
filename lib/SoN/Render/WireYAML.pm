# ABOUTME: The wire JSON as compact flow YAML, one node per line, a node's id its
# ABOUTME: list index -- the graph listing in pvm's corpus `ir` blocks.

use v5.42.0;

package SoN::Render::WireYAML;

use JSON::PP ();

# render($wire) -> YAML text
#
# THE WIRE, TRANSCRIBED, in a form any YAML parser reads:
#
#   main::sign: {start: 0, returns: [14], nodes: [
#     [Start], # 0
#     [NumLt, ~, [6, 7], ~, Boolean], # 8
#     [Region, {head: 9}, [10, 11]], # 12
#     [Return, ~, [13], 12]]} # 14
#
# A top-level map from graph name (methods by name, then each phase block as
# `BEGIN n` / `END n`) to {start, returns, nodes}. `nodes` is a LIST whose index
# is the node's id -- the serializer numbers every graph densely from 0, so the
# index is the id and a reference is an index -- and the comment repeats it for
# a reader. Each node is
#
#   [op, fields, inputs, control_in, stamp]
#
# with `~` where the wire has nothing and trailing `~`s dropped. A Region's
# `head` rides in its fields map, which keeps every node to five positions.
#
# EVERY SCALAR KEEPS ITS WIRE TYPE. It is encoded as JSON first, so a number
# stays a number and a string stays a string ("50" is not 50), and a string is
# left bare only where YAML cannot read it as anything else.
#
# ponytail: graphs only. The sub records, classes and data section are not
# written; add them when a consumer stage needs them from the corpus.
my $JSON = JSON::PP->new->canonical->allow_nonref->ascii;

sub render ($wire) {
    my $out = '';
    my $methods = $wire->{methods} // {};
    $out .= _graph($_, $methods->{$_}) for sort keys %$methods;
    my $i = 0;
    $out .= _graph(($_->{phase} // 'PHASE') . ' ' . ++$i, $_)
        for ($wire->{phase_blocks} // [])->@*;
    return $out;
}

sub _graph ($name, $g) {
    my @nodes = sort { $a->{id} <=> $b->{id} } ($g->{nodes} // [])->@*;
    for my $i (0 .. $#nodes) {
        die "WireYAML: $name node ids are not dense from 0 (position $i holds"
          . " id $nodes[$i]{id}); the list index could not be the id\n"
            unless $nodes[$i]{id} == $i;
    }
    my $head = sprintf '%s: {start: %s, returns: %s, nodes: [',
        _scalar($name), _scalar($g->{start}), _list($g->{returns} // []);
    return "$head]}\n" unless @nodes;

    my @lines;
    for my $n (@nodes) {
        my %f = %{ $n->{fields} // {} };
        $f{head} = $n->{head} if defined $n->{head};
        my @parts = (
            _scalar($n->{op}),
            (%f ? '{' . join(', ', map { _scalar($_) . ': ' . _value($f{$_}) }
                                   sort keys %f) . '}' : '~'),
            (@{ $n->{inputs} // [] } ? _list($n->{inputs}) : '~'),
            _scalar($n->{control_in}),
            _scalar($n->{stamp}),
        );
        pop @parts while @parts > 1 && $parts[-1] eq '~';
        push @lines, [ '  [' . join(', ', @parts) . ']', $n->{id} ];
    }
    $lines[-1][0] .= ']}';
    return "$head\n"
         . join('', map { $_ == $#lines ? "$lines[$_][0] # $lines[$_][1]\n"
                                        : "$lines[$_][0], # $lines[$_][1]\n" }
                    0 .. $#lines);
}

sub _list ($a) { '[' . join(', ', map { _value($_) } @$a) . ']' }

sub _value ($v) {
    return _list($v) if ref $v eq 'ARRAY';
    return '{' . join(', ', map { _scalar($_) . ': ' . _value($v->{$_}) }
                           sort keys %$v) . '}' if ref $v eq 'HASH';
    return _scalar($v);
}

# Words YAML 1.1 or 1.2 would read as a boolean or null.
my %SPECIAL = map { $_ => 1 } qw(y n yes no true false on off null);

sub _scalar ($v) {
    return '~' unless defined $v;
    my $j = $JSON->encode($v);
    # A number, as the wire has it.
    return $j unless $j =~ /\A"/;
    # A string YAML cannot mistake: starts with a letter, `_` or `$`, holds
    # only word characters, `:`, `.`, `$` and `-`, and is not a special word.
    return $v if $v =~ /\A[A-Za-z_\$][\w:.\$\-]*\z/a
        && $v !~ /:\z/ && !$SPECIAL{ lc $v };
    # Otherwise JSON's quoting, which is YAML's double-quoted style -- except
    # that YAML does not join a surrogate pair, so one becomes \U.
    $j =~ s{\\u(d[89ab][0-9a-f]{2})\\u(d[c-f][0-9a-f]{2})}{
        sprintf '\\U%08X',
            0x10000 + ((hex($1) - 0xD800) << 10) + (hex($2) - 0xDC00) }gie;
    return $j;
}

1;
