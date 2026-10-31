package N { sub new { bless { i => $_[1] }, $_[0] } sub inputs { $_[0]{i} } }
sub upd { my ($phi) = @_; my $inputs = $phi->inputs; return "none" unless defined $inputs && @$inputs; my $init = $inputs->[0]; return "i=$init" }
print upd(N->new([7])), " ", upd(N->new([])), "\n";
