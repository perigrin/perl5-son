# ABOUTME: And/Or render as short-circuit operators, and the short circuit must be preserved.
# ABOUTME: Verified by running: an eagerly-evaluated RHS shows up as extra output.

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

# `&&` AND `||` ARE SHORT-CIRCUIT, and that is observable rather than a detail
# of evaluation order: if the RHS has an effect, an eager rendering RUNS it
# when perl would not. So each case below puts an effect in the RHS and the
# output says whether the short circuit survived.
subtest 'short-circuit is preserved' => sub {
    round_trips('my $f = 0; my $r = $f && print("rhs\n"); print "done\n";',
        '&& does not run its RHS when the LHS is false');
    round_trips('my $t = 1; my $r = $t || print("rhs\n"); print "done\n";',
        '|| does not run its RHS when the LHS is true');
    round_trips('my $t = 1; my $r = $t && print("rhs\n"); print "done\n";',
        '&& DOES run its RHS when the LHS is true');
    round_trips('my $f = 0; my $r = $f || print("rhs\n"); print "done\n";',
        '|| DOES run its RHS when the LHS is false');
};

# THE VALUE OF `&&`/`||` IS AN OPERAND, not a boolean: `0 || "x"` is "x", not
# 1. Rendering them as a boolean test would agree on truthiness and disagree on
# the value, which is the same class of defect as `==` for `eq`.
subtest 'the value is an operand, not a boolean' => sub {
    round_trips('my ($a,$b) = (0, "x"); print $a || $b, "\n";', 'or yields the operand');
    round_trips('my ($a,$b) = (2, 3); print $a && $b, "\n";',   'and yields the operand');
    round_trips('my ($a,$b) = (undef, 5); print $a // $b, "\n";', 'defined-or');
};

subtest 'xor and not' => sub {
    round_trips('my ($a,$b) = (1, 0); print(($a xor $b) ? "y\n" : "n\n");', 'Xor');
    round_trips('my $a = 0; print((!$a) ? "y\n" : "n\n");', 'Not');
};

done_testing;
