package P { sub new { bless { v => $_[1] }, $_[0] } sub v { $_[0]{v} } sub inc { $_[0]{v}++ } } my $o = P->new(3); $o->inc for 1 .. 2; print $o->v, "\n";
