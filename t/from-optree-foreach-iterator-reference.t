# ABOUTME: A reference to a foreach iterator is refused by name: the lowering binds a
# ABOUTME: copy and writes it back each pass, and a reference can outlive the pass.

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

sub produce ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    open my $eh, '<', "$dir/err" or die $!;
    my $err = do { local $/; <$eh> } =~ s/^\S+ syntax OK\n//mr;
    return (eval { JSON::PP->new->decode($j) }, $err);
}

my $GAP = qr/GAP: a reference to a foreach iterator is not yet lowered/;

sub refused ($src, $name) {
    my (undef, $err) = produce($src);
    like $err, $GAP, "$name: refused by name";
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ($data, $err) = produce($src);
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) { fail "$name: renders"; diag $d->gap; return }
    is run_perl($out), $want, $name or diag $out;
}

# perl prints 5: the reference is the caller's element.
refused(<<'SRC', 'a reference carried out of the loop');
sub f { my $n = 0; for my $x (@_) { $n = \$x } $$n = 5; return $n }
my @a = (1); f(@a); print "$a[0]\n";
SRC

refused(<<'SRC', 'the same, from a reference init');
sub f { my $z; my $n = \$z; for my $x (@_) { $n = \$x } $$n = 5; return $n }
my @a = (1); f(@a); print "$a[0]\n";
SRC

refused(<<'SRC', 'a reference kept on a guard');
my @a = (1,2,3); my $r; for my $x (@a) { $r = \$x if $x == 2 } $$r = 9; print "@a\n";
SRC

refused(<<'SRC', 'a reference pushed onto an outer array');
my @a = (1,2,3); my @r; for my $x (@a) { push @r, \$x } ${$r[1]} = 9; print "@a\n";
SRC

refused(<<'SRC', 'a reference stored into a hash');
my @a = (1,2,3); my %h; for my $x (@a) { $h{$x} = \$x } ${$h{3}} = 9; print "@a\n";
SRC

refused(<<'SRC', 'a reference handed to a sub that keeps it');
sub keep { our $K = $_[0] } my @a = (1,2); for my $x (@a) { keep(\$x) } $$K = 7; print "@a\n";
SRC

# A range iterator aliases nothing the program can see again.
round_trips(<<'SRC', 'references to a range iterator');
my @r; for my $i (1..3) { push @r, \$i } print join(",", map { $$_ } @r), "\n";
SRC

# Passing the iterator itself, not a reference, keeps its write-back.
round_trips(<<'SRC', 'an iterator passed to a sub that writes it');
sub bump { $_[0]++ } my @a = (1,2); for my $x (@a) { bump($x) } print "@a\n";
SRC

done_testing;
