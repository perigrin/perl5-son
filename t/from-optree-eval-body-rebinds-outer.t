# ABOUTME: A block eval whose body rebinds a variable from outside it is refused by
# ABOUTME: name: the trap's join does not carry what the body stored before a die.

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

my $GAP = qr/GAP: a block eval whose body rebinds a variable from outside it/;

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

# perl prints b: the store before the die survives the unwind.
refused(<<'SRC', 'a loop in an eval carries a value out past a die');
sub f { my $n = 0; eval { for my $x (@_) { $n = $x; die "d\n" if $x eq "b" } }; return $n }
print f("a","b","c"), "\n";
SRC

refused(<<'SRC', 'an Unknown init, the same loop');
sub f { my $n = $_[9]; eval { for my $x (@_) { $n = $x; die "d\n" if $x eq "b" } }; return $n // "u" }
print f("a","b","c"), "\n";
SRC

refused(<<'SRC', 'a range loop');
sub f { my $n = 0; eval { for my $i (1..3) { $n = $i; die "d\n" if $i == 2 } }; return $n }
print f(), "\n";
SRC

# The while is not a rebinding the trap drops: the body walk STOPS at the
# enterloop it has no case for, and the whole loop vanished -- perl prints 2.
like((produce(<<'SRC1'))[1], qr/GAP: a block eval body stopped at `enterloop`/, "a while loop: refused by name");
sub f { my $n = 0; eval { my $i = 0; while ($i < 3) { $i++; $n = $i; die "d\n" if $i == 2 } }; return $n }
print f(), "\n";
SRC1

# The same drop with nothing outside rebound: perl prints 1 2 3.
like((produce(<<'SRC2'))[1], qr/GAP: a block eval body stopped at `enterloop`/, "a while loop that only prints: refused by name");
sub f { eval { my $i = 0; while ($i < 3) { $i++; print "$i\n" } 1 } } f();
SRC2

# No loop at all: perl prints 5.
refused(<<'SRC', 'a straight-line store then die');
sub f { my $n = 0; eval { $n = 5; die "d\n" }; return $n }
print f(), "\n";
SRC

# The common idiom, and no die: perl prints 7.
refused(<<'SRC', 'a store from a call, then a true value');
sub g { 7 } sub f { my $x = 0; eval { $x = g(); 1 }; return $x }
print f(), "\n";
SRC

# A body that only declares and reads its own lexicals rebinds nothing outside.
round_trips(<<'SRC', 'an eval whose body keeps to its own lexicals');
sub f { my $n = 3; my $r = eval { my $t = $n + 1; die "d\n" if $_[0]; $t } // -1; return "$n $r" }
print f(0), " ", f(1), "\n";
SRC

# A package variable is stored through memory, which the trap does carry.
round_trips(<<'SRC', 'a package variable stored in the body');
our $g = 0; sub f { eval { $g = 1; die "d\n" if $_[0]; $g = 2; 1 }; print "$g\n" } f(1); f(0);
SRC

done_testing;
