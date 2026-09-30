# ABOUTME: `foreach` over `@$r`, `$r->@*` or `$obj->method->@*` iterates the
# ABOUTME: referent's elements, aliased -- not a single reference value.

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
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
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

# THE DEREFERENCE WAS DROPPED. In a sub, the loop's list was the REFERENCE
# itself -- a Call or Subscript -- and the walker refused "foreach with
# unrecognized bounds shape": 244 skipped graphs across chalk's lib/, the
# commonest loop there being `for my $x ($self->{items}->@*)`.
round_trips(<<'SRC', 'a dereferenced array in a sub');
sub total { my $r = shift; my $t = 0; for my $x (@$r) { $t += $x } $t }
print total([1, 2, 3]), "\n";
SRC

round_trips(<<'SRC', 'postfix deref of a hash element, as chalk writes it');
sub names { my $s = shift; my @out; for my $x ($s->{items}->@*) { push @out, uc $x } join ",", @out }
print names({ items => ["a", "b"] }), "\n";
SRC

round_trips(<<'SRC', 'a method returning an array reference');
package Bag { sub new { bless { xs => [4, 5] }, shift } sub xs { $_[0]{xs} } }
sub sum_bag { my $b = shift; my $t = 0; for my $x ($b->xs->@*) { $t += $x } $t }
print sum_bag(Bag->new), "\n";
SRC

# THE LOOP VARIABLE ALIASES THE REFERENT'S ELEMENTS: a write is visible
# through the reference afterwards.
round_trips(<<'SRC', 'a write through the loop variable reaches the referent');
sub double { my $r = shift; for my $x (@$r) { $x *= 2 } }
my $a = [1, 2, 3];
double($a);
print "@$a\n";
SRC

done_testing;
