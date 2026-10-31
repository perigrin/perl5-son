use v5.42.0; use Scalar::Util qw(blessed refaddr);
use Chalk::IR::Serialize::JSON; use Chalk::Target::LLVM;
my $json = do { local (@ARGV,$/) = shift; <> };
my $gs = Chalk::IR::Serialize::JSON::from_json($json);
my %own;
for my $k (sort keys %$gs) { $own{refaddr $_} //= $k for grep { blessed $_ } $gs->{$k}->nodes->@* }
for my $k (sort keys %$gs) {
  my @c = Chalk::Target::LLVM::Context::_graph_component($gs->{$k});
  my %by; $by{ $own{refaddr $_} // '?' }++ for @c;
  my @sh = grep { $_->operation eq 'Call' && ($_->name//'') eq 'shift' } @c;
  say "$k: component ", scalar(@c), " nodes by owner: ", join(', ', map {"$_=$by{$_}"} sort keys %by), "; shifts=", scalar(@sh), " [", join(',', map { $own{refaddr $_}//'?' } @sh), "]";
}
my %in; for my $k (sort keys %$gs) { for (Chalk::Target::LLVM::Context::_graph_component($gs->{$k})) { $in{refaddr $_}{$k}=$_ } }
for my $a (keys %in) { my @k = sort keys $in{$a}->%*; next unless @k > 1; my ($n) = values $in{$a}->%*; say "shared: ", $n->operation, " id=", $n->id, " owner=", ($own{$a}//'?'), " in ", join(',', @k) }
