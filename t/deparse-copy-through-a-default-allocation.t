# ABOUTME: A list copied through `E // []` or `E || []` is read after the branch that
# ABOUTME: allocates its fallback joins, and still before any later write.

use v5.42.0;
use Test2::V0;
use JSON::PP;
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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK
//mr;
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
        my $g = $d->gap // '(no reason)'; $g =~ s/
.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---
$out--- got ---
$got--- want ---
$want";
}
round_trips(<<'SRC', 'two defaults to an allocation, each dereferenced');
package O { sub new { bless { i => $_[1] }, $_[0] } sub inputs { $_[0]{i} } }
sub f { my ($d) = @_; my ($l) = ($d->inputs // [])->@*; my ($c) = ($l->inputs // [])->@*; return $c // 0 }
print f(O->new([O->new([5])])), f(O->new([O->new(undef)])), "\n";
SRC

round_trips(<<'SRC', 'chalk DefinedOrFold::_fold, reduced');
package O { sub new { bless { i => $_[1] }, $_[0] } sub inputs { $_[0]{i} } }
sub fold { my ($dor) = @_; my ($lhs, $rhs) = ($dor->inputs // [])->@*;
    return 'no lhs' unless defined $lhs;
    my ($c, $i) = ($lhs->inputs // [])->@*; return defined $i ? "$c$i" : 'no index' }
print fold(O->new(undef)), " ", fold(O->new([O->new([1, 2])])), " ", fold(O->new([O->new(undef)])), "\n";
SRC

# THE COPY STILL HAPPENS BEFORE A LATER WRITE. Read after the join, not
# left live, so a push after it is not seen.
round_trips(<<'SRC', 'a copy of E // [] taken before a push');
my @g = (1, 2); sub g { $_[0] ? \@g : undef }
sub f { my @s = sort((g($_[0]) // [])->@*); push @g, 3; return "@s|@g" }
print f(1), " ", f(0), "\n";
SRC

round_trips(<<'SRC', 'the same with ||');
my @g = (1, 2); sub g { $_[0] ? \@g : undef }
sub f { my @s = sort((g($_[0]) || [])->@*); push @g, 3; return "@s|@g" }
print f(1), " ", f(0), "\n";
SRC

done_testing;
