# EnvRead, ArgsSource
$ENV{SON_FIXTURE} = "set";
print "$ENV{SON_FIXTURE}\n";
sub takes_args { my @a = @_; return scalar(@a) }
print takes_args(1,2,3), "\n";
