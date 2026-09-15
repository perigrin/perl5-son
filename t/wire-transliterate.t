# ABOUTME: tr/// is its own operation, not a regex substitution.
# ABOUTME: Its from/to are character SETS; compiling them as a pattern miscompiles.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graph_of ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return $data->{methods}{'main::__PROGRAM__'};
}

# `trans` mapped to a generic Call, so the 522-byte translation table the
# PVOP carries was dropped entirely: `Call(trans, [target])` with no from, no
# to, and nothing a consumer could use. base/lex.t reaches it as `tr[a][b]`.
#
# NOT A RegexSubst. The from/to are character SETS, and `tr/a-z/A-Z/` read as
# a regex means something else entirely -- reusing that node would be a
# miscompile by construction rather than a missing field.
subtest 'a transliteration names its character sets' => sub {
    my $g = graph_of(qq{\$_ = "a";\ntr[a][b];\nprint "\$_\\n";\n});
    ok defined $g, 'it translates' or return;

    my ($tr) = grep { $_->{op} eq 'Transliterate' } $g->{nodes}->@*;
    ok defined $tr, 'a Transliterate is in the graph' or return;

    is $tr->{fields}{from}, 'a', 'the source set survives';
    is $tr->{fields}{to},   'b', 'and so does the replacement set';
};

# A RANGE stays a range -- the decoder gives back the source spelling rather
# than the expanded table, so the emitted program is the same size.
subtest 'a range round-trips as a range' => sub {
    my $g = graph_of(qq{my \$s = "hello";\n\$s =~ tr/a-z/A-Z/;\nprint "\$s\\n";\n});
    ok defined $g, 'it translates' or return;

    my ($tr) = grep { $_->{op} eq 'Transliterate' } $g->{nodes}->@*;
    ok defined $tr, 'a Transliterate is in the graph' or return;
    is $tr->{fields}{from}, 'a-z', 'the range is not expanded';
    is $tr->{fields}{to},   'A-Z', 'on either side';
};

# `tr/x//d` DELETES rather than replacing, and an empty `to` does not say so:
# `tr/x//` with no flags maps x to itself. The flag must be on the wire.
subtest 'the delete flag is carried' => sub {
    my $g = graph_of(qq{my \$s = "axb";\n\$s =~ tr/x//d;\nprint "\$s\\n";\n});
    ok defined $g, 'it translates' or return;

    my ($tr) = grep { $_->{op} eq 'Transliterate' } $g->{nodes}->@*;
    ok defined $tr, 'a Transliterate is in the graph' or return;
    like $tr->{fields}{flags}, qr/d/, 'the d flag is on the node';
};

done_testing;
