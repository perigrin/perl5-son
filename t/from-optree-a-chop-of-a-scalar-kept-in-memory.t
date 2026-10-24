# ABOUTME: chop/chomp of a scalar kept in memory (handed to a call) stores the
# ABOUTME: trimmed string back, as sassign does, instead of binding it.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src));
    is run_perl($out // ''), run_perl($src), $name
        or diag $out // $d->gap;
}

# A SCALAR HANDED TO A CALL IS READ THROUGH MEMORY, so a trim bound to its
# slot reached no read: the Chomp floated with no consumer, and the program
# printed abcabc for perl's abcab.
round_trips(<<'SRC', 'chop of a scalar handed to a call');
sub ld { $_[0] }
my $s = "abc"; print ld($s); chop($s); print ld($s), "\n";
SRC

round_trips(<<'SRC', 'chomp, and the count it yields');
sub ld { $_[0] }
my $s = "ab\n"; print ld($s), "|"; my $n = chomp($s); print ld($s), " $n\n";
SRC

round_trips(<<'SRC', 'chop in a sub, of its own memory-kept scalar');
sub ld { $_[0] }
sub f { my $t = shift; my $r = ld($t); my $c = chop $t; return "$r " . ld($t) . " $c" }
print f("xyz"), "\n";
SRC

done_testing;
