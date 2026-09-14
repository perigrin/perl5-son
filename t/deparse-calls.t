# ABOUTME: Call renders by dispatch kind -- a builtin, a named sub, or a method.
# ABOUTME: Verified by RUNNING the rendered program; a wrong callee is a wrong answer.

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

# THREE DISPATCH KINDS, and the wire discriminates them consistently. Measured
# across the seven blocked corpus files: 105 direct, 19 builtin, 8 method, and
#
#     direct   always carries `want`, never `class_name`
#     builtin  carries neither
#     method   always carries `class_name`
#
# A direct call names a sub the graph also emits, so the emitted program must
# DEFINE it too -- a call to a sub that does not exist is a runtime death, not
# a wrong value, which is why this is checked by running.
subtest 'a builtin call' => sub {
    round_trips('my @a = (3,1,2); print join(",", sort { $a <=> $b } @a), "\n";',
        'join + sort');
    # `keys` ROUND-TRIPS NOW. It refused while the graph gave it a HashLiteral
    # with no name and no memory -- the defect docs/plans/2026-09-06 recorded.
    # The producer now carries both (the aggregate's name, and the memory the
    # read observes), so the emitter has a container to name and an ordering
    # to respect.
    #
    # THE MEMORY INPUT IS AN EDGE, NOT AN ARGUMENT: emitting it would put a
    # MemStart in the argument list. And the STAMP carries the context -- a
    # counted `keys` is stamped Int, and emitting the list form for it printed
    # the keys themselves ("ba" where perl printed 2).
    round_trips('my %h = (a=>1,b=>2); print scalar(keys %h), "\n";',
        'keys in scalar context');
    round_trips('my %h = (a=>1); $h{b}=2; print scalar(keys %h), "\n";',
        'keys observes a store');
    round_trips('my $s = "abc"; print length($s), "\n";', 'length');
};

subtest 'a direct call to a named sub' => sub {
    round_trips('sub f { return 42 } print f(), "\n";', 'no args');
    round_trips('sub add { my ($x,$y) = @_; return $x + $y } print add(2,3), "\n";',
        'with args');
    round_trips('sub g { return "g" } sub h { return "h" } print g(), h(), "\n";',
        'two subs');
};

# A VOID CALL IS AN EFFECT and must still be emitted: dropping it loses
# whatever the sub did. It reaches the emitter as a control-chain node rather
# than as an operand of something.
subtest 'a void call' => sub {
    round_trips('sub shout { print "loud\n" } shout(); print "after\n";',
        'void call in the chain');
};

done_testing;
