# ABOUTME: A foreach over a literal list has no array, and its store is the alias.
# ABOUTME: `for (LIST)` is the spelling; a named temporary would be a DIFFERENT container.

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

# A FOREACH OVER A LITERAL LIST HAS NO ARRAY. Measured on comp/fold.t's
# `for (\(1+3)) { ... $$_++ }`:
#
#     15 Ref          in=[14]        stamp=ScalarRef
#     16 ArrayLiteral in=[15]        stamp=Array, NO symbol
#     17 Count        in=[16, 2]
#
# so the iteration source is an anonymous list and the loop indexes it. The
# emitter refused an element store into it, correctly in general -- but here
# the container needs no name at all: `for (LIST)` is the spelling, and the
# element read IS the aliased `$_`.
#
# A NAMED TEMPORARY WOULD BE A DIFFERENT CONTAINER, which is exactly what the
# refusal exists to prevent -- so the check is that the value the loop writes
# is visible afterwards through the SAME storage, not merely that something
# rendered.
subtest 'a foreach over a literal list' => sub {
    # AN EXPLICIT LOOP VARIABLE, because the implicit `$_` alias is
    # separately broken in the producer -- see the note below. What this
    # checks is the literal list as an iteration SOURCE.
    round_trips(<<'SRC', 'three elements, read in order');
my @seen;
for my $x (1, 2, 3) { push @seen, $x * 10 }
print "@seen\n";
SRC

    # THE COUNT IS THE POINT, and `(1,2,3)` hides it: `scalar((1,2,3))` is 3
    # by coincidence, because the comma operator yields the LAST ELEMENT and
    # it happens to equal the count. `(5,2,9)` does not -- measured,
    # `scalar((5,2,9))` is 9 -- and a loop bounded by that runs past its end.
    round_trips(<<'SRC', 'a list whose last element is not its count');
my @seen;
for my $x (5, 2, 9) { push @seen, $x }
print scalar(@seen), " [@seen]\n";
SRC
};

# A NAMED ARRAY MUST NOT REGRESS -- it has a container to assign through and
# is the common case.
#
# THE IMPLICIT `$_` ALIAS IS SEPARATELY BROKEN in the producer, pinned in
# t/from-optree-foreach-alias-binds.t: the body reads `EntryDef $main::_` whose
# memory is MemStart, so nothing binds it to the element. Only a loop that
# READS the alias hits that, so this case uses an explicit variable -- a case
# failing for two reasons proves neither.
subtest 'a foreach over a named array' => sub {
    round_trips(<<'SRC', 'the alias writes the array');
my @a = (1, 2);
for my $x (@a) { $x = $x * 10 }
print "@a\n";
SRC
};

done_testing;
