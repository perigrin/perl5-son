use v5.42.0;
use lib '/home/perigrin/dev/chalk/lib', '/home/perigrin/dev/chalk/t/lib';
use Chalk::IR::Serialize::JSON; use JSON::PP;
my $json = do { local (@ARGV, $/) = shift; <> };
my $wire = decode_json($json);
my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
for my $n (sort keys %$graphs) { my @ops = map { $_->operation } grep { blessed $_ } $graphs->{$n}->nodes->@*; say "$n: wire nodes=", scalar @{$wire->{methods}{$n}{nodes}}, " graph->nodes=", scalar(@ops), " Assigns in graph->nodes=", scalar(grep { $_ eq 'Assign' } @ops), " in wire=", scalar(grep { $_->{op} eq 'Assign' } @{$wire->{methods}{$n}{nodes}}) }
