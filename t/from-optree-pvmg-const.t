# ABOUTME: Tests SoN::FromOptree decodes PVMG constants by FLAGS, not by class isa().
# ABOUTME: A v-string is a POK-only PVMG whose isa('B::IV') is true; it must not decode as 0.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# B's SV classes nest: PVMG isa PV, isa NV, isa IV. So a dispatch chain that
# asks isa('B::IV') first claims every richer SV, including ones carrying only
# a string. A v-string is exactly that shape -- PVMG with POK set and neither
# IOK nor NOK -- so it took the integer arm and returned its empty IV slot.
#
# The content matters, not the spelling: v65.66 IS "AB" (chr 65, chr 66). The
# version-number syntax is how you write it and `sprintf "%vd"` is how you
# render it back, so a test that checks the version rendering can pass while
# the bytes are gone.

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub const_of ($code) {
    my $g = graph_of($code);
    my ($c) = grep {
        $_->operation eq 'Constant' && ($_->const_type // '') ne 'undef'
    } $g->nodes->@*;
    return $c;
}

subtest 'a v-string constant keeps its bytes' => sub {
    my $c = const_of('sub { my $v = v65.66; $v }');
    ok(defined $c, 'found a Constant') or return;

    is($c->const_type, 'string', 'decodes as a string, not an integer');
    is($c->value, "AB", 'value is the two characters, not 0');
    is($c->stamp->type, 'Str', 'stamped Str');
};

subtest 'a v-string of unprintable ordinals survives too' => sub {
    # Guards against a fix that only works when the bytes happen to be ASCII.
    my $c = const_of('sub { my $v = v1.2.3; $v }');
    ok(defined $c, 'found a Constant') or return;

    is($c->const_type, 'string', 'decodes as a string');
    is([ map { ord } split //, ($c->value // '') ], [ 1, 2, 3 ],
        'ordinals are 1,2,3');
};

subtest 'ordinary constants still decode by their own flags' => sub {
    # The fix reorders the dispatch, so the common shapes are the regression
    # surface: an integer must not become a string just because it is also
    # stringifiable.
    my $int = const_of('sub { my $x = 42; $x }');
    is($int->const_type, 'integer', '42 is an integer');
    is($int->value, 42, 'value 42');
    is($int->stamp->type, 'Int', 'stamped Int');

    my $num = const_of('sub { my $x = 3.5; $x }');
    is($num->const_type, 'number', '3.5 is a number');
    is($num->value, 3.5, 'value 3.5');
    is($num->stamp->type, 'Num', 'stamped Num');

    my $str = const_of('sub { my $x = "hello"; $x }');
    is($str->const_type, 'string', '"hello" is a string');
    is($str->value, 'hello', 'value hello');
    is($str->stamp->type, 'Str', 'stamped Str');

    # A numeric-looking STRING stays a string -- the quotes are the fact.
    my $numstr = const_of('sub { my $x = "42"; $x }');
    is($numstr->const_type, 'string', '"42" is a string, not an integer');
    is($numstr->value, '42', 'value "42"');
};

done_testing;
