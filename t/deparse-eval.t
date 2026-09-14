# ABOUTME: A string eval renders as `eval`, and its Region is the join it creates.
# ABOUTME: The Phi(value, undef) says the effect may have died; that IS eval's value.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# A SINGLE-PREDECESSOR REGION IS AN EVAL'S JOIN, not a branch's. Measured on
# `my $v = eval "1+1"`:
#
#     4 Coerce  in=[3]   ci=0   Str->Code     the eval itself
#     5 Region  in=[4]                        one control input
#     6 Phi     in=[4,1] region=5             [value, undef]
#
# and the producer says why: "the eval either yielded its value or caught and
# returned undef. Two arms merging is the same shape block eval builds."
#
# The control side has ONE edge because the failure path produces no separate
# control -- only the VALUE forks. That is exactly what Perl's `eval` is, so
# the Region needs no spelling of its own: it is discharged by the closing
# brace, like an If's join.
subtest 'a string eval round-trips' => sub {
    round_trips(<<'SRC', 'a value-producing eval');
my $v = eval "1+1";
print "[$v]\n";
SRC

    # THE FAILURE PATH IS THE POINT. An eval that dies must yield undef and
    # leave $@ set, not propagate -- a renderer that dropped the eval would
    # abort here rather than print.
    round_trips(<<'SRC', 'an eval that dies');
my $v = eval "die qq(boom\\n)";
print "[", (defined $v ? $v : "undef"), "][$@]";
SRC
};

# A BRANCH AFTER AN EVAL. comp/bproto.t is this shape, and the eval Region
# blocked the walk before the If was ever reached -- so the one-armed join was
# never the failure it appeared to be.
subtest 'a branch after an eval' => sub {
    round_trips(<<'SRC', 'if after eval, one-armed');
eval "die qq(x\\n)";
print "caught " if $@;
print "done\n";
SRC

    round_trips(<<'SRC', 'if after eval, not taken');
eval "1";
print "caught " if $@;
print "done\n";
SRC
};

done_testing;
