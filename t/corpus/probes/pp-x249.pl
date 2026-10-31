use feature 'class';
no warnings 'experimental::class';
class Node {
    method parts { my @p; push @p, "a", "b"; return @p }
    method hash  { return join("|", "op", $self->parts) }
    method count { my $c = $self->parts; return $c }
}
print Node->new->hash, " ", Node->new->count, "\n";
