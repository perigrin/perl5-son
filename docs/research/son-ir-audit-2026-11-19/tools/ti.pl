# ti.pl wire.json -- run chalk's TypedInvariant::check over each graph of a wire (read-only use of chalk's lib)
use v5.42.0;
use lib '/home/perigrin/dev/chalk/lib', '/home/perigrin/dev/chalk/t/lib';
use Chalk::IR::Serialize::JSON; use Chalk::IR::Graph::TypedInvariant;
my $json = do { local (@ARGV, $/) = shift; <> };
my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
for my $n (sort keys %$graphs) { my $r = eval { Chalk::IR::Graph::TypedInvariant->check($graphs->{$n}) }; if (!$r) { say "$n: check died: $@"; next } say "$n: ", ($r->{ok} ? "ok" : "VIOLATIONS: " . join("; ", map { "$_->{node_id}: $_->{message}" } @{$r->{violations}}[0 .. ($#{$r->{violations}} > 5 ? 5 : $#{$r->{violations}})])) }
