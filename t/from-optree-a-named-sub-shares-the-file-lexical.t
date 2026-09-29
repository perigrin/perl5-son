# ABOUTME: A named sub that reads or writes a file-level `my` shares that one
# ABOUTME: variable with the program: it is a location in both graphs.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# A TIME LIMIT, as for every loop test: a wrong lowering can spin.
sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; diag producer_stderr(); return;
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

# THE PROGRAM FOLDED THE VARIABLE AWAY AND THE SUB READ NOTHING. `get()` is an
# opaque call, so nothing in the program's graph read `$x` and `my $x = 5`
# never reached the wire; the sub's `$x` was a read of nothing, emitted above
# a program body that declared no `$x` for it. perl records the sharing on
# the sub's pad (PADNAMEf_OUTER, PARENT_PAD_INDEX). See
# docs/plans/2026-09-29-a-named-sub-shares-the-file-lexical.md.
round_trips(<<'SRC', 'a named sub reads a file lexical');
my $x = 5;
sub get { $x }
print get(), "\n";
SRC

# A WRITE IN THE SUB IS SEEN BY THE PROGRAM, so the call is ordered against
# the program's reads of the variable.
round_trips(<<'SRC', 'a named sub writes a file lexical');
my $count = 0;
sub bump { $count++ }
bump(); bump();
print "$count\n";
sub add { $count = $count + $_[0] }
add(10);
print "$count\n";
SRC

# A SUB COMPILED BEFORE THE `my` does not share it: at that point no lexical
# `$v` exists, so the sub names the package variable `$main::v` and prints
# `v=` twice. It must not be mistaken for a sharing sub.
round_trips(<<'SRC', 'a sub defined above the lexical it reads');
sub show { print "v=$v\n" }
my $v = 3;
show();
$v = 4;
show();
SRC

# AN ARRAY, read by element and whole. Corpus 201.
round_trips(<<'SRC', 'a named sub reads a file array');
my @l = ($ENV{A} // "a", "b");
sub pair { return $l[0], $l[1]; }
sub one { return $l[0]; }
my @p = pair();
print scalar(@p), one(), "\n";
print "@p\n";
SRC

# A CODE REFERENCE in a file lexical, called from a sub. Corpus 200.
round_trips(<<'SRC', 'a named sub calls a coderef held in a file lexical');
my $show = sub { return "[@_]" };
sub outer { return "amp=" . &$show . " paren=" . &$show(); }
print outer("x", "y"), "\n";
print $show->(), "\n";
SRC

# AN :lvalue SUB returning the shared lexical is assigned through. Corpus 199.
round_trips(<<'SRC', 'an lvalue sub over a file lexical');
my $slot = 0;
sub slot :lvalue { $slot }
slot() = 42;
print slot(), "\n";
SRC

# A DEMOTED SLOT IS STORED BY `++` AND `+=` AS BY `=`. They rebound the value
# instead, so a read through the reference saw the first value.
round_trips(<<'SRC', 'increments and compound stores on a referenced slot');
my $x = 1; my $r = \$x;
$x++; my $y = $x++; ++$x; $x += 2;
print "$$r $y\n";
SRC

done_testing;
