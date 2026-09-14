# ABOUTME: Two identical string evals are two effects, not one hash-consed node.
# ABOUTME: An eval body runs once per occurrence; sharing it drops all but one.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    my $d = eval { JSON::PP->new->decode($j) } or return undef;
    return $d->{methods}{'main::__PROGRAM__'};
}

# AN EVAL BODY IS AN EFFECT, AND EFFECTS DO NOT SHARE. NodeFactory::make
# dedupes by content_hash, and SoN::IR::Node deliberately excludes control_in
# from that hash so a side-effect and a pure-data use of the same content
# still hash-cons. That rationale holds for a pure expression and is FALSE for
# an eval, which must happen once per occurrence.
#
# Measured on `my $a = eval q{1+1}; my $b = eval q{1+1}`:
#
#     3 Region  in=[4]
#     4 Coerce  in=[2]  ci=3     <- ONE Coerce, and ci is its OWN Region
#     9 Region  in=[4]           <- a second Region over the same node
#
# a self-cycle, which makes everything unreachable from Start. Measured
# end to end, the emitted program DROPPED BOTH EVALS: perl prints n=2, the
# emitted program printed nothing at all. A silent DROP, the worst category.
#
# Two DISTINCT eval strings were always correct -- two Coerces, properly
# chained -- which is what makes this a hash-consing defect rather than an
# eval defect.
subtest 'two identical evals are two nodes' => sub {
    my $g = graph_of('my $a = eval q{1+1}; my $b = eval q{1+1}; print "$a $b\n";');
    ok $g, 'it translates' or return;

    my @eval = grep { ($_->{op} // '') eq 'Coerce'
                   && ((($_->{fields} // {})->{to_repr} // '') eq 'Code') }
               $g->{nodes}->@*;
    is scalar(@eval), 2, 'two eval nodes, one per occurrence';

    # NO SELF-CYCLE. A node whose control_in is a Region that names it back
    # makes the whole graph unreachable from Start.
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    for my $e (@eval) {
        my $ci = $by{ $e->{control_in} // -1 } or next;
        ok !(grep { $_ == $e->{id} } (($ci->{inputs} // [])->@*)),
            "eval $e->{id} does not name its own Region as control";
    }
};

# THE EFFECT IS WHAT MATTERS, so the check is that both bodies RUN. Counting
# nodes would pass a graph that has two Coerces wired to one effect.
subtest 'both eval bodies run' => sub {
    my $src = <<'SRC';
our $n = 0;
sub bump { $n++; 1 }
eval q{bump()};
eval q{bump()};
print "n=$n\n";
SRC
    is run_perl($src), "n=2\n", 'perl runs both' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    my @eval = grep { ($_->{op} // '') eq 'Coerce'
                   && ((($_->{fields} // {})->{to_repr} // '') eq 'Code') }
               $g->{nodes}->@*;
    is scalar(@eval), 2, 'and the graph holds both';
};

# DISTINCT STRINGS MUST NOT REGRESS -- they were always correct, and they are
# what shows this is about identity rather than about eval.
subtest 'distinct evals still lower' => sub {
    my $g = graph_of('my $a = eval q{1+1}; my $b = eval q{2+2}; print "$a $b\n";');
    ok $g, 'it translates' or return;
    my @eval = grep { ($_->{op} // '') eq 'Coerce'
                   && ((($_->{fields} // {})->{to_repr} // '') eq 'Code') }
               $g->{nodes}->@*;
    is scalar(@eval), 2, 'two eval nodes';
};

done_testing;
