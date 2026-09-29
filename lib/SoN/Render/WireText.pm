# ABOUTME: The wire JSON as a text listing, one node per line: the ids, inputs,
# ABOUTME: control edges and stamps a consumer loads, for pvm's corpus `ir` blocks.

use v5.42.0;

package SoN::Render::WireText;

use JSON::PP ();

# render($wire) -> text
#
# A LISTING OF THE WIRE, NOT OF THE PRODUCER'S GRAPH. SoN::Render::Text walks
# the in-memory graph: its ids are pre-remap, it shows no control edges, and
# its stamps predate the post-pass -- so it describes a graph no consumer
# loads. This reads the JSON a consumer reads, and says only what is there.
#
#   == main::f start=%0 returns=%8
#   %3 = Call dispatch_kind=direct name=main::g want=list (%2) ctl=%0 : Str
#
# One header per graph (methods by name, then phase blocks in order), then its
# nodes by id: `%ID = OP FIELDS (INPUTS) ctl=%C head=%H : STAMP`, each part
# present only when the wire has it. Fields are in key order; a field that
# names a node (region, predecessors) is spelled as a node.
#
# ponytail: graphs only. The sub records, classes and data section are not
# listed; add them when a consumer stage needs them from the corpus.
my %NODE_FIELD = map { $_ => 1 } qw(region predecessors);

sub render ($wire) {
    my $out = '';
    my $methods = $wire->{methods} // {};
    $out .= _graph("$_", $methods->{$_}) for sort keys %$methods;
    my $i = 0;
    $out .= _graph(($_->{phase} // 'PHASE') . ' ' . ++$i, $_)
        for ($wire->{phase_blocks} // [])->@*;
    return $out;
}

sub _graph ($name, $g) {
    my $out = sprintf "== %s start=%s returns=%s\n", $name,
        _ref($g->{start}), join(',', map { _ref($_) } ($g->{returns} // [])->@*);
    for my $n (sort { $a->{id} <=> $b->{id} } ($g->{nodes} // [])->@*) {
        my @parts = ("%$n->{id} =", $n->{op});
        my $f = $n->{fields} // {};
        for my $k (sort keys %$f) {
            my $v = $f->{$k};
            push @parts, "$k=" . ($NODE_FIELD{$k} ? _refs($v) : _value($v));
        }
        my @in = ($n->{inputs} // [])->@*;
        push @parts, '(' . join(', ', map { _ref($_) } @in) . ')' if @in;
        push @parts, 'ctl=' . _ref($n->{control_in}) if defined $n->{control_in};
        push @parts, 'head=' . _ref($n->{head}) if defined $n->{head};
        push @parts, ': ' . $n->{stamp} if defined $n->{stamp};
        $out .= join(' ', @parts) . "\n";
    }
    return $out;
}

sub _ref ($id) { defined $id ? "%$id" : '-' }

sub _refs ($v) {
    return ref $v eq 'ARRAY' ? '[' . join(',', map { _ref($_) } @$v) . ']' : _ref($v);
}

my $JSON = JSON::PP->new->canonical->allow_nonref;

# A bare word when it reads unambiguously, else JSON -- which escapes a
# newline, so a value never breaks its line.
sub _value ($v) {
    return 'undef' unless defined $v;
    return $v if !ref $v && $v =~ /\A[\w:.\$\@%&+\-]+\z/;
    return $JSON->encode($v);
}

1;
