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
    # STDOUT ONLY: the emission runs under warnings the source may not.
    my $out = qx($^X $f 2>/dev/null); unlink $f; return $out;
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

# A RECURSIVE CLOSURE: `my $w; $w = sub { ... $w->(...) }`. The anon sub is
# built first and makes $w's cell; the store into $w after it named that
# cell, matched no store rule, and was dropped -- the emitted program called
# undef ("Can't use an undefined value as a subroutine reference"). chalk's
# EmitHelpers::_collect_all_var_refs walks a schedule so.
round_trips(q{sub f { my $w; $w = sub { my $n = shift; return $n <= 0 ? 0 : $n + $w->($n - 1) }; return $w->(3) } print f(), "\n";},
    'a recursive closure, stored after it is made');
round_trips(q{use v5.38; sub f ($k) { my $w; $w = sub { my $n = shift; return $n <= 0 ? 0 : $k + $w->($n - 1) }; return $w->(3) } print f(2), "\n";},
    'a recursive closure over its sub\'s parameter');

# `//=` INTO AN ELEMENT THROUGH A CAPTURED REFERENCE writes the referent,
# which the closure and its maker share.
round_trips(q{use v5.38; sub collect ($tree, $dv) { my $walk; $walk = sub ($node) { return unless ref $node; $dv->{$node->{name}} //= 1 if exists $node->{name}; for my $k ($node->{kids}->@*) { $walk->($k) } }; $walk->($tree); return join ",", sort keys %$dv } print collect({ kids => [{ name => 'a', kids => [] }, { name => 'b', kids => [{ name => 'a', kids => [] }] }] }, { z => 0 }), "\n";},
    'a //= through a captured reference, in a recursive closure');
# A CAPTURED AGGREGATE was refused here: its lifted body read a fresh one
# (`1 2` for perl's `1 1`). Shared with its sub (below), it is one hash.
round_trips(q{sub g { my %h; my $f = sub { $h{$_[0]} //= $_[1] }; return join " ", $f->("a", 1), $f->("a", 2) } print g(), "\n";},
    'a //= into a captured hash');

# AN AGGREGATE A CLOSURE CAPTURES FROM ITS SUB is one array in both: the
# maker read its own SSA value past the calls (`join($", 5)` for perl's
# `5 1 2`), and the lifted body declared a fresh `my @p` of its own. It is
# shared as a file lexical a named sub uses is: stored and read through
# memory, declared once above the subs. chalk's Earley fills
# `@pending_sweeps` from a commit callback and drains it in the maker.
round_trips(q{sub f { my @p = (5); my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); return "@p" } print f(), "\n";},
    'a closure pushes onto its sub\'s array, read after the calls');
round_trips(q{sub f { my @p = (5); my $c = sub { push @p, $_[0] }; @p = (); $c->(1); $c->(2); return "@p" } print f(), "\n";},
    'the sub clears the array, then the closure fills it');
round_trips(q{sub f { my %h; my $c = sub { $h{$_[0]}++ }; $c->("a"); $c->("a"); $c->("b"); return join ",", map { "$_=$h{$_}" } sort keys %h } print f(), "\n";},
    'a closure counts into its sub\'s hash');
round_trips(q{sub f { my @p; my $c = sub { push @p, $_[0] }; my $o = ""; for my $i (1 .. 3) { $c->($i); $o .= scalar(@p) } return "$o:@p" } print f(), "\n";},
    'the sub reads the array in a loop the closure fills');
# THE SUB'S READ IS A READ AT ITS POINT, and its clear is a store at its
# point. With the slot bound to its container both floated: `"@p"` was
# spelled after the later clear and call (`1 2 3` for `5 1 2`), and the
# clear's literal was declared above the calls it was to follow (`1 2` for
# `2`). The held read is an array, not its count.
round_trips(q{sub f { my @p = (5); my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); my $a = "@p"; @p = (); $c->(3); return "$a/@p" } print f(), "\n";},
    'the sub reads the array, clears it, and the closure refills it');
round_trips(q{sub f { my @p = (5); my $c = sub { push @p, $_[0] }; $c->(1); @p = (); $c->(2); return "@p" } print f(), "\n";},
    'the sub clears the array between two calls');
round_trips(q{sub f { my %h = (a => 1); my $c = sub { $h{$_[0]} = 1 }; my @k = sort keys %h; $c->("b"); my @l = sort keys %h; %h = (); $c->("c"); return join ",", @k, "|", @l, "|", sort keys %h } print f(), "\n";},
    'the sub reads the hash between the closure\'s stores');

# A SHARED AGGREGATE IS FRESH ON EACH CALL of its sub, as its `my` is: shared
# by name it is one file-level variable, and a bare `my @p;` left no store,
# so a second call saw the first's elements -- chalk's Dominators built its
# block map on top of the last graph's and never finished.
round_trips(q{sub mk { my @p; my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); return "@p" } print mk(), "|", mk(), "\n";},
    'a closure\'s array is fresh on each call of its sub');
round_trips(q{sub mk { my %h; my $c = sub { $h{$_[0]}++ }; $c->("a"); $c->("b"); return join ",", map { "$_=$h{$_}" } sort keys %h } print mk(), "|", mk(), "\n";},
    'a closure\'s hash is fresh on each call of its sub');

done_testing;
