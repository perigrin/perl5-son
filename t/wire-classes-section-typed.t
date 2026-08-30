# ABOUTME: A classful payload carries its field types and body reprs ON THE WIRE
# ABOUTME: -- the producer answers this, so no loader is needed to recover it.
use v5.42.0;
use Test2::V0;
use JSON::PP ();
use File::Temp ();

# WHAT THIS REPLACES, AND WHY IT IS NOT A WEAKER TEST. This was
# t/from-json-classes-branch.t, which drove a classful payload through a
# VENDORED COPY OF CHALK'S LOADER (SoN::IR::Serialize::JSON) and asserted that
# the loader's inference reconstructed the field type and the body reprs.
#
# The producer now answers all of it directly: `field $n = 5` reaches the wire
# with type Int, Counter::val's FieldAccess with Int, Counter::plus's Add with
# Int -- the same three values the loader was being credited for deriving. So
# the assertions move to the wire, which is where this repo's contract actually
# lives. A test that loads is testing the CONSUMER; this repo is the producer.
#
# The regression the old test guarded is preserved and is the real point: a
# previous trim (82e97cc) gutted the classes branch believing it dead, and it
# was not -- it ran four inference passes, threw the results away, then died,
# and nothing went red. The equivalent failure now is a classes section that
# reaches the wire untyped, and that is exactly what these assertions catch.
sub wire ($src, $pkg) {
    my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} $src;
    close $fh;
    my $json = qx{$^X -Ilib -Iblib/lib -MO=SoN,json,package=$pkg $tmp 2>/dev/null};
    return JSON::PP::decode_json($json);
}

my $SRC = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n = 5;
    method val  { $n }
    method plus { $n + 1 }
}
PERL

my $d = wire($SRC, 'Counter');

subtest 'the payload carries a classes section' => sub {
    ok exists $d->{classes}{Counter}, 'the class is on the wire' or return;
    my ($f) = ($d->{classes}{Counter}{fields} // [])->@*;
    ok $f, 'the field record exists' or return;
    is $f->{name}, '$n', 'it is $n';
    is $f->{type}, 'Int', 'and it carries its declared type -- no loader needed';
};

# THE LOAD-BEARING HALF. These reprs exist only because the producer's
# inference chain ran; an untyped classes section leaves them Unknown.
subtest 'the method bodies are typed on the wire' => sub {
    my $val = $d->{methods}{'Counter::val'};
    ok $val, 'Counter::val is on the wire' or return;
    my ($fa) = grep { $_->{op} eq 'FieldAccess' } $val->{nodes}->@*;
    ok $fa, 'Counter::val has a FieldAccess' or return;
    is $fa->{stamp}, 'Int', 'the field read carries the field type';

    my $plus = $d->{methods}{'Counter::plus'};
    ok $plus, 'Counter::plus is on the wire' or return;
    my ($add) = grep { $_->{op} eq 'Add' } $plus->{nodes}->@*;
    ok $add, 'Counter::plus has an Add' or return;
    is $add->{stamp}, 'Int', 'and the type propagated past the field read';
};

done_testing;
