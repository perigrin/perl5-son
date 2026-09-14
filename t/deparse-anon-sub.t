# ABOUTME: An AnonSub is a reference to its body, which is emitted as its own sub.
# ABOUTME: The wire name has colons and digits in it, so it needs a legal identifier.

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

# AN AnonSub IS A REFERENCE TO ITS BODY, and the body is already a separate
# `methods` entry that the emitter writes out as a named sub -- measured on
# `my $c = sub { 8 }; print ref($c), " ", $c->(), "\n"`:
#
#     methods: main::__PROGRAM__, main::__PROGRAM__::__ANON__:1:2
#     2 AnonSub  name=main::__PROGRAM__::__ANON__:1:2
#     5 Call     direct name=main::__PROGRAM__::__ANON__:1:2
#
# so the value and the call name the same body, and `\&that` is the reference.
#
# THE WIRE NAME IS NOT AN IDENTIFIER. It carries the definition site as
# `:LINE:SEQ`, so `sub __PROGRAM__::__ANON__:1:2 {...}` does not parse -- the
# name has to be mangled to something legal, consistently everywhere it
# appears, or the reference and the definition stop matching.
subtest 'an anon sub used as a value' => sub {
    round_trips(<<'SRC', 'ref() of it, and calling it');
my $c = sub { 8 };
print ref($c), " ", $c->(), "\n";
SRC
};

# TWO ANON SUBS AT DIFFERENT SITES must stay distinct: the name carries the
# site precisely so two `sub { }` with identical bodies are two subs.
subtest 'two anon subs stay distinct' => sub {
    round_trips(<<'SRC', 'two bodies, different answers');
my $a = sub { 1 };
my $b = sub { 2 };
print $a->(), $b->(), "\n";
SRC

    round_trips(<<'SRC', 'two bodies, identical text');
my $a = sub { 7 };
my $b = sub { 7 };
print $a->(), $b->(), "\n";
SRC
};

done_testing;
