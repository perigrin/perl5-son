# ABOUTME: BlessedRef is any blessed reference; Object is the class feature's
# ABOUTME: instance (reftype OBJECT) under it; a qr// (reftype REGEXP) is a sibling.

use 5.42.0;
use utf8;
use Test::More;
use SoN::IR::Stamp;
use B::SoN::TypeLibrary;

sub S ($t) { SoN::IR::Stamp->new(type => $t) }
sub below ($l, $r) { S($l)->is_subtype_of(S($r)) }

# Measured on 5.42.0: class F -> blessed F, reftype OBJECT; bless {} -> HASH;
# qr// -> blessed Regexp, reftype REGEXP. All blessed; only the first is Object.
ok below('BlessedRef', 'Ref'),        'a BlessedRef is a Ref';
ok below('Object', 'BlessedRef'),     'an Object (class instance) is a BlessedRef';
ok below('Regex', 'BlessedRef'),      'a qr// is a BlessedRef';
ok !below('Regex', 'Object'),         'a qr// is not a class instance';
is SoN::IR::Stamp::join(S('Object'), S('Regex'))->type, 'BlessedRef', 'their join is BlessedRef';

# CORE.tpm's Object means any blessed reference: read as BlessedRef.
my $r = sub ($n) { B::SoN::TypeLibrary::result_for( [ 'Call', $n ] ) };
is $r->('bless'),   undef,               'bless returns its argument: no fixed row';
is $r->('dbmopen'), 'Maybe[BlessedRef]', 'dbmopen a BlessedRef or undef';

done_testing;
