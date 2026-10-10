# ABOUTME: A push, shift or reference taken inside a branch arm is seen by a later list read
# ABOUTME: of the array: the arm's mutation reaches the main walk, so the read observes memory.

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


round_trips('my @a=(1,2); my $c=1; my $x = $c ? push(@a,3) : 0; print "$x @a\n";',
    'a push in a ternary arm, its value kept');
round_trips('my @a=(1,2); my $c=1; $c ? push(@a,3) : 0; print "@a\n";',
    'a push in a ternary arm, in void context');
round_trips('my @a=(1,2); my $c=1; if ($c) { push @a, 3 } print "@a\n";',
    'a push in an if block');
round_trips('my @a=(1,2); my $c=1; $c && push(@a,3); print "@a\n";',
    'a push behind a short circuit');
round_trips('my @a=(1,2); my $c=1; $c ? unshift(@a,3) : shift(@a); print "@a\n";',
    'an unshift and a shift in the two arms');
round_trips('sub f { my @a=(1,2); my $c = shift; $c ? push(@a,3) : 0; return "@a" } print f(1), "|", f(0), "\n";',
    'a push in an arm inside a sub, both ways');
round_trips('my @a=(1,2); my $c=0; $c ? push(@a,3) : 0; my @b = @a; print "@b\n";',
    'an arm not taken leaves the array as built');
round_trips('my @a=(1,2); my $c=1; my $r = $c ? \@a : 0; push @$r, 4; print "@a\n";',
    'a reference taken in an arm, pushed through after');
round_trips('my @a=(1,2); for my $i (1..2) { push @a, $i } print "@a\n";',
    'a push in a loop body');

# A WHOLE-ARRAY REASSIGN AFTER THE PUSH. The graph holds two values named @a,
# the array as built and the one the reassign builds, and the read names the
# second. Spelled with one name, the reassign was hoisted above the push and
# the push landed on the new array.
round_trips(q{my @a=(1,2); my $c=1; if ($c) { push @a, 3 } @a = (); print "[@a]\n";},
    q{a push in an if block, then the array cleared});
round_trips(q{my @a=(1,2); my $c=1; $c ? push(@a,3) : 0; @a = (); print "[@a]\n";},
    q{a push in a ternary arm, then the array cleared});
round_trips(q{my @a=(1,2); for my $i (1..2) { push @a, $i } @a = (); print "[@a]\n";},
    q{a push in a loop body, then the array cleared});
round_trips(q{my @a=(1,2); my $c=1; if ($c) { push @a, 3 } @a = (7,8); print "@a\n";},
    q{a push in an if block, then the array reassigned});
round_trips(q{my @a=(1,2); my $c=1; if ($c) { push @a, 3 } my @b=@a; @a=(7,8); print "@b|@a\n";},
    q{a copy taken before the reassign keeps the pushed element});
round_trips(q{my @a=(1,2); for my $i (1..2) { push @a, $i } @a = (7); print "@a\n";},
    q{a push in a loop body, then the array reassigned});
round_trips(q{my @a=(1,2); push @a,3; @a = (7,8); push @a, 9; print "[@a]\n";},
    q{a push on each side of a reassign});
round_trips(q{my %h=(a=>1); $h{b}=2; %h=(); print join(",", sort keys %h), "\n";},
    q{a hash store, then the hash cleared});

done_testing;
