# ABOUTME: A block eval whose body rebinds a lexical from outside it refuses by name:
# ABOUTME: the write survives a die partway through, and the eval's single join cannot say so.

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

sub producer ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    open my $eh, '<', "$dir/err"; local $/; my $err = <$eh> =~ s/^\S+ syntax OK\n//mr;
    return ($j, $err);
}

my $WHY = qr/GAP: a block eval whose body rebinds a variable from outside it is not yet lowered/;

# THE BODY'S BINDINGS NEVER LEFT IT. The eval merged only memory and control
# back, so every write to an outer lexical vanished: perl 1, emitted 0.
for my $src (
    'my $s=0; eval { $s++ }; print "$s\n";',
    'my $s=0; eval { $s = 5; 1 } or print "x"; print "$s\n";',
    'my $s=0; my $r = eval { $s = 5; 7 }; print "$s $r\n";',
    'my $s=0; eval { for my $i (1..3) { $s++ } }; print "$s\n";',
    'my $s=0; eval { for my $i (1..3) { my $j=0; while ($j<2) { $s++; $j++ } } }; print "$s\n";',
    'my $s=0; for my $i (1..3) { eval { $s += $i } } print "$s\n";',
) {
    my (undef, $err) = producer($src);
    like $err, $WHY, "refuses: $src";
}

# A BODY THAT TOUCHES ONLY ITS OWN LEXICALS still lowers and still runs.
for my $src (
    'my $s=0; my $r = eval { my $t = 4; $t += 1; $t }; print "$s $r\n";',
    'my $s=3; my $r = eval { $s * 2 }; print "$r\n";',
    'my $s=0; eval { print "in\n" }; print "$s\n";',
    # A package variable's store rides the eval's memory out.
    'our $g=0; eval { $g = 5; die "x\n" }; print "$g\n";',
    'our $g=0; for my $i (1..3) { eval { $g += $i } } print "$g\n";',
) {
    my ($j, $err) = producer($src);
    is $err, '', "lowers: $src";
    my $d = SoN::Deparse->new;
    my $out = $d->render(JSON::PP->new->decode($j)) // '';
    is run_perl($out), run_perl($src), "round trips: $src";
}

done_testing;
