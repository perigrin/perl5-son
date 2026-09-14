# ABOUTME: A list assign to already-declared variables rebinds them, like `my (...) = ...`.
# ABOUTME: Separating the declaration from the assignment must not lose the values.

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

# THE READS MUST NAME THE VARIABLES, not resolve to the pre-assignment undef.
# Measured on `my ($a,$b); ($a,$b) = (1,2); print "$a$b"` -- perl prints 12,
# and the graph's Print cone held a bare `Constant undef` where $a and $b
# should be: the assignment's targets were never rebound, so every later read
# saw the declaration's undef. A silent miscompile in an ordinary construct.
#
# `my ($a,$b) = (1,2)` -- declaration and assignment together -- was always
# correct and reads through PadAccess, which is what makes this about the
# REBIND rather than about list assignment.
#
# CHECKED AS BEHAVIOUR, not as node shapes: the two spellings produce
# different but equally valid graphs (one reads PadAccess, the other resolves
# through the binding), so only running the emitted program separates a
# correct rebind from a lost one.
use SoN::Deparse;

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $g = graph_of($src);
    unless ($g) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render({ methods => { 'main::__PROGRAM__' => $g } });
    unless (defined $out) {
        fail "$name: renders";
        diag(($d->gap // '?') =~ s/\n.*//sr);
        return;
    }
    is run_perl($out), $want, $name;
}

subtest 'a separated list assign rebinds its targets' => sub {
    round_trips('my ($a,$b); ($a,$b) = (1,2); print "$a$b\n";',
                'declared first, assigned after');
};

# FEWER VALUES THAN TARGETS is the same question with an undef in it, and the
# undef belongs to the TRAILING target, not to every one.
subtest 'fewer values than targets' => sub {
    round_trips('my ($a,$b,$c); ($a,$b,$c) = (1,2);'
              . ' print "$a$b", (defined $c ? "c" : "-"), "\n";',
                'two values, three targets');
};

# THE COMBINED FORM MUST NOT REGRESS -- it was always correct and is the
# common spelling.
subtest 'declaration and assignment together' => sub {
    round_trips('my ($a,$b) = (1,2); print "$a$b\n";', 'both at once');
};

done_testing;
