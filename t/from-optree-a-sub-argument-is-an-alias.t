# ABOUTME: A lexical passed to a sub is passed by alias: the callee can write
# ABOUTME: it through @_, so it is address-taken exactly as `\$x` makes it.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
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

# A WRITE THROUGH @_ REACHES THE CALLER'S VARIABLE. The argument was left a
# value binding, so the caller's later read folded to the constant it was
# declared with. Corpus 029: perl `2 1`, emitted `1 1`.
round_trips(<<'SRC', 'a callee writes through $_[0]');
sub bump_alias { $_[0]++ }
sub bump_copy { my ($n) = @_; $n++ }
my ($aliased, $untouched) = (1, 1);
bump_alias($aliased);
bump_copy($untouched);
print "$aliased $untouched\n";
SRC

# THE ARGUMENT IS THE LOCATION, so the call's operand is the lvalue pad
# access -- and the value-only binding it replaced had folded the `my` away:
# `sq($n)` over an undeclared $n. Corpus 202.
round_trips(<<'SRC', 'a lexical argument is declared where the call can see it');
my $n = $ENV{X} // 3;
*sq = sub { $_[0] * $_[0] };
print sq($n), " ", $n * 2, "\n";
SRC

done_testing;
