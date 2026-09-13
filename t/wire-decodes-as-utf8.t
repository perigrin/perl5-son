# ABOUTME: The wire must decode as UTF-8 under a decoder that is not perl's.
# ABOUTME: A string Constant holding a character above U+007F reached it as a raw byte.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub wire_of ($src) {
    my $f = "$dir/w." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!;
    binmode $fh, ':raw';
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    $out =~ s/\A.*?(?=\{)//s;   # strip the "syntax OK" preamble
    return $out;
}

# THE PRODUCER WRITES THE WIRE AND THE PRODUCER'S TESTS READ IT BACK, which is
# how this went unnoticed: perl's JSON decoder accepts a document perl wrote
# whatever its encoding. Anything else refuses. Python's json.load on
# base/num.t:
#
#     UnicodeDecodeError: utf-8 codec can't decode byte 0xf0 in position 149111
#
# The values arriving at the serializer are CHARACTER strings -- measured, a
# "café" literal and a high-byte string both reach it with utf8_flag=ON -- so
# encoding them once, as ->utf8 does, is what a byte-oriented wire needs.
#
# NOT ->ascii. It is also correct, and it optimises for the pathological case
# at the cost of every ordinary one: "café" becomes "café" and the wire
# grows ~60% for any program containing non-ASCII text.
subtest 'a wire carrying a high character decodes as UTF-8' => sub {
    my $wire = wire_of(qq{my \$s = "caf\x{c3}\x{a9}"; print \$s, "\\n";});
    ok length $wire, 'it produced a wire' or return;

    my $copy = $wire;
    ok utf8::decode($copy), 'the wire decodes as UTF-8';
};

# A DELIBERATELY MALFORMED STRING IS THE HARD CASE. perl's own
# t/comp/parser.t holds one, and the whole point of that test is the bytes --
# so the round trip must return them unchanged, not merely produce valid JSON.
subtest 'a high-byte string round-trips through the wire' => sub {
    my $wire = wire_of(qq{my \$s = "q\\xff\\x80"; print length(\$s), "\\n";});
    ok length $wire, 'it produced a wire' or return;

    my $copy = $wire;
    ok utf8::decode($copy), 'the wire decodes as UTF-8';

    my $data = eval { JSON::PP->new->utf8->decode($wire) };
    ok $data, 'and decodes as JSON' or diag $@;

    my ($const) = grep {
        ($_->{op} // '') eq 'Constant'
            && defined $_->{fields}{value}
            && $_->{fields}{value} =~ /\x{ff}/
    } ($data->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    ok $const, 'the high-byte Constant survived the round trip'
        or return;
    is $const->{fields}{value}, "q\x{ff}\x{80}",
        '... with its exact characters, not re-encoded';
};

done_testing;
