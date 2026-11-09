# ABOUTME: Maybe[T] is T|Undef in the producer's lattice: a stamp of it is made, T and
# ABOUTME: Undef are below it, it is below Scalar, a join keeps it, a meet with T narrows it.

use 5.42.0;
use utf8;
use Test::More;
use SoN::IR::Stamp;

sub S ($t) { SoN::IR::Stamp->new(type => $t) }
sub J ($l, $r) { SoN::IR::Stamp::join(S($l), S($r))->type }
sub M ($l, $r) { SoN::IR::Stamp::meet(S($l), S($r))->type }
sub below ($l, $r) { S($l)->is_subtype_of(S($r)) }

ok eval { S('Maybe[Boolean]'); 1 }, 'a Maybe[Boolean] stamp is made' or diag $@;
ok !eval { S('Maybe[Nope]'); 1 },  'not over a type the lattice does not know';

ok below('Boolean', 'Maybe[Boolean]'),    'T <: Maybe[T]';
ok below('Undef', 'Maybe[Boolean]'),      'Undef <: Maybe[T]';
ok below('Int', 'Maybe[Num]'),            'a subtype of T is below Maybe[T]';
ok below('Maybe[Int]', 'Maybe[Num]'),     'Maybe is covariant';
ok below('Maybe[Boolean]', 'Scalar'),     'Maybe[T] <: Scalar';
ok !below('Maybe[Boolean]', 'Boolean'),   'Maybe[T] is not below T';

is J('Maybe[Boolean]', 'Undef'),   'Maybe[Boolean]', 'a join absorbs Undef';
is J('Maybe[Boolean]', 'Boolean'), 'Maybe[Boolean]', 'a join absorbs T';
is J('Maybe[Int]', 'Num'),         'Maybe[Num]',     'a join joins the T parts';
is J('Maybe[Boolean]', 'Str'),     'Scalar',         'Maybe[Scalar] is Scalar';
is J('Boolean', 'Undef'),          'Maybe[Boolean]', 'stage 2: join(T, Undef) is Maybe[T]';
is J('Undef', 'Int'),              'Maybe[Int]',     '... either side';
is J('Array', 'Undef'),            'List',           'an aggregate with Undef keeps the tree join';

is M('Maybe[Boolean]', 'Boolean'), 'Boolean', 'a meet with T is T';
is M('Maybe[Boolean]', 'Undef'),   'Undef',   'a meet with Undef is Undef';

done_testing;
