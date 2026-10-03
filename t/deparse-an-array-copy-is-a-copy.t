# ABOUTME: `my @q = @_` (or a field, or a dereference) is a COPY: mutating @q leaves the
# ABOUTME: source alone. Only a fresh aggregate value -- a map result -- is taken as it is.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
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


# A SINGLE AGGREGATE RHS WAS BOUND AS THE TARGET -- right for a fresh value,
# which nothing else names, and wrong for storage: `my @q = @_; shift @q`
# rendered `shift(@_)`, and @_ lost an element (perl 32, emitted 22).
# chalk's worklists start `my @q = ...` from an argument or a field.
round_trips(<<'SRC', 'a copy of @_ is shifted');
sub f { my @q = @_; shift @q; return scalar(@_) . scalar(@q) } print f(1, 2, 3), "\n";
SRC

round_trips(<<'SRC', 'a copy of @_ is pushed');
sub f { my @q = @_; push @q, 9; return scalar(@_) . scalar(@q) } print f(1, 2, 3), "\n";
SRC

round_trips(<<'SRC', 'a copy of a field');
use v5.42; use experimental 'class';
class C { field @a = (1, 2); method m { my @q = @a; shift @q; return scalar(@a) . scalar(@q) } }
print C->new->m, "\n";
SRC

round_trips(<<'SRC', 'a copy of a dereference');
sub f { my $r = shift; my @q = @$r; pop @q; return scalar(@$r) . scalar(@q) } print f([1, 2, 3]), "\n";
SRC

round_trips(<<'SRC', 'a map result is taken as it is');
sub f { my @q = map { $_ * 2 } @_; shift @q; return "@q" } print f(1, 2, 3), "\n";
SRC

done_testing;
