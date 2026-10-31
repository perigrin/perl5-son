use v5.36;
use feature 'class';
no warnings 'experimental::class';
class Node { field $id :param; method id { return $id } }
sub ids ($in) { return join(",", map { defined($_) ? $_->id : "undef" } $in->@*) }
sub fib ($n) { return $n < 2 ? $n : fib($n - 1) + fib($n - 2) }
print ids([Node->new(id => 1), undef, Node->new(id => 3)]), " ", fib(10), "\n";
