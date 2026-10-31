use v5.42.0; use Scalar::Util qw(blessed refaddr);
use Chalk::IR::Serialize::JSON; use Chalk::Target::LLVM;
my $json = do { local (@ARGV,$/) = shift; <> };
my $gs = Chalk::IR::Serialize::JSON::from_json($json);
for my $k (sort keys %$gs) {
  for my $n (Chalk::Target::LLVM::Context::_graph_component($gs->{$k})) {
    next unless $n->operation eq 'Proj';
    my @cons = map { $_->operation.'('.$_->id.')' } grep { blessed $_ } ($n->consumers//[])->@*;
    my $ci = $n->can('control_in') && blessed($n->control_in) ? $n->control_in->id : '-';
    say "$k: Proj ", $n->id, " refaddr=", refaddr($n), " in=", join(',', map { blessed $_ ? $_->id : '?' } $n->inputs->@*), " ctl=$ci consumers=@cons";
  }
}
