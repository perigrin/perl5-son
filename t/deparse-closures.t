# ABOUTME: A captured lexical is a cell: MakeCell/CellParam/CellRead/CellWrite.
# ABOUTME: Two closures over one cell must see each other's writes, which is the point.

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

# A CAPTURED LEXICAL IS A CELL. Measured on two closures over one `my $n`:
#
#     13 MakeCell   in=[1, 5]  captured_written=1 cell_name='$n'
#     14 AnonSub    in=[13]    captures=['$n']
#     15 AnonSub    in=[13]    captures=['$n']
#   -- in each body:
#      1 CellParam  index=0 name='$n'
#      3 CellRead   in=[1, 2]
#      6 CellWrite  in=[1, 5, 2]  ci=0
#
# THE BODIES ARE SEPARATE `methods` ENTRIES, emitted as named subs -- so the
# cell cannot be a `my` inside either of them. It has to be a variable they
# both close over, declared where MakeCell is.
#
# TWO CLOSURES OVER ONE CELL SEEING EACH OTHER'S WRITES IS THE WHOLE POINT,
# and it is what a wrong spelling breaks silently: give each sub its own copy
# and the program still runs, printing 0 or 1 instead of 2.
subtest 'two closures share one cell' => sub {
    round_trips(<<'SRC', 'a writer and a reader');
my $n = 0;
my $inc = sub { $n = $n + 1 };
my $rd  = sub { return $n };
$inc->(); $inc->();
print $rd->(), "\n";
SRC
};

# A CELL WRITE IS VISIBLE TO THE ENCLOSING SCOPE TOO, not only to sibling
# closures -- the outer `$n` and the cell are the same storage.
subtest 'the enclosing scope sees the write' => sub {
    round_trips(<<'SRC', 'outer read after an inner write');
my $n = 5;
my $bump = sub { $n = $n + 10 };
$bump->();
print "$n\n";
SRC
};

# A CAPTURE THAT IS ONLY READ needs no cell in the general case, and must keep
# working either way.
subtest 'a read-only capture' => sub {
    round_trips(<<'SRC', 'captured but never written');
my $k = 7;
my $get = sub { return $k };
print $get->(), "\n";
SRC
};

done_testing;
