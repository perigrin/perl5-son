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
    # `keys` OVER A LITERAL AGGREGATE IS REFUSED, and the refusal is the
    # oracle earning its keep. The graph gives keys a HashLiteral -- a LIST --
    # with no container to name, and `keys(("a",1))` is a compile error. The
    # emitter could bind a temporary and make this pass, and that would be
    # exactly wrong: the known defect here (docs/plans/2026-09-06) is about
    # WHICH container a read observes, so a spelled-around round-trip would
    # agree with itself and hide it.
    my $d = SoN::Deparse->new;
    my $data = graph_of('my %h = (a=>1,b=>2); print scalar(keys %h), "\n";');
    ok $data, 'the keys program translates' or return;
    my $out = $d->render($data);
    is $out, undef, 'keys over a literal aggregate refuses rather than guessing';
    like $d->gap, qr/no container to name/,
        '... naming the reason, and pointing at the open defect';
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
