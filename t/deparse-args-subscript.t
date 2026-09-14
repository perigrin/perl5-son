# ABOUTME: An element of @_ is an array element, not a dereference.
# ABOUTME: `@_->[0]` is a syntax error; the aggregate's stamp says which it is.

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

# THE ARGUMENT ARRAY IS AN ARRAY. `@_` has stamp Array, so an element of it is
# `$_[0]`. Rendering the operand's spelling followed by `->[0]` produces
# `@_->[0]`, which does not compile: "Can't use an array as a reference".
# Found by the oracle on comp/redef.t, whose every `ok` sub indexes @_.
round_trips(<<'SRC', 'an element of @_');
sub ok { print join('', ($_[1] ? "ok " : "not ok "), $_[0], "\n") }
ok(1, 1);
ok(2, 0);
SRC

# A REAL REFERENCE STILL DEREFERENCES. The stamp is what separates them, so
# the ArrayRef case must keep the arrow it needs.
round_trips(<<'SRC', 'an element of an array ref');
my $r = [10, 20, 30];
print $r->[1], "\n";
SRC

done_testing;
