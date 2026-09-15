# ABOUTME: chomp/chop mutate in place, so the graph must record the store.
# ABOUTME: Without it the following read still names the pre-chomp value.

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

# `chomp($s)` compiles to `schomp`, which mutates its operand. The producer
# emitted `Call(schomp, [PadAccess])` consumed by NOBODY, so the graph said
# nothing about the mutation and the following read still named the ORIGINAL:
#
#     my $s = "ab\n"; chomp($s); print "[$s]"
#       perl : [ab]
#       graph: the Print reading the pre-chomp Constant "ab\n"
#
# The deparser could not spell it either -- `schomp` is not a keyword -- so
# this was an undefined sub call before it was refused.
subtest 'a chomp is consumed by something' => sub {
    my $g = graph_of(qq{my \$s = "ab\\n";\nchomp(\$s);\nprint "[\$s]\\n";\n});
    ok defined $g, 'it translates' or return;

    my ($chomp) = grep { ($_->{op} // '') eq 'Chomp' } $g->{nodes}->@*;
    ok defined $chomp, 'a Chomp is in the graph' or return;

    # The store is what proves the mutation is recorded. A node nothing reads
    # is a node the emitted program can drop.
    my @readers = grep {
        my $n = $_;
        grep { ($_ // -1) == $chomp->{id} } ($n->{inputs} // [])->@*
    } $g->{nodes}->@*;
    ok scalar(@readers), 'and something consumes it';
};

# chop removes the LAST character whatever it is; chomp removes only a
# trailing $/. Two operations, and the node must say which.
subtest 'chop and chomp are distinguished' => sub {
    my $gc = graph_of(qq{my \$s = "abc";\nchop(\$s);\nprint "\$s\\n";\n});
    ok defined $gc, 'chop translates' or return;
    my ($chop) = grep { ($_->{op} // '') eq 'Chomp' } $gc->{nodes}->@*;
    ok defined $chop, 'a Chomp node carries chop too' or return;
    is $chop->{fields}{kind}, 'chop', 'and says it is a chop';

    my $gm = graph_of(qq{my \$s = "ab\\n";\nchomp(\$s);\nprint "\$s\\n";\n});
    my ($chomp) = grep { ($_->{op} // '') eq 'Chomp' } $gm->{nodes}->@*;
    is $chomp->{fields}{kind}, 'chomp', 'while chomp says chomp';
};

done_testing;
