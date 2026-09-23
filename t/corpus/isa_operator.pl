# IsaOp
use v5.42.0;
package Animal { sub new { bless {}, shift } }
package Dog { our @ISA = ('Animal'); sub new { bless {}, shift } }
my $d = Dog->new;
print(($d isa Animal) ? "yes" : "no", "\n");
print(($d isa Dog) ? "yes" : "no", "\n");
