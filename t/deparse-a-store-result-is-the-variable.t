# ABOUTME: A store's result is the variable itself: an append whose value reads its own
# ABOUTME: target declares first, and a store result a later operand stores again refuses.

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

sub round_trips ($src) {
    my $want = run_perl($src);
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "renders: $src"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, "round trips: $src"
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

sub refuses ($src) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    ok !defined $out, "refuses: $src" or diag $out;
    like producer_stderr(), qr/GAP: a scalar operand is read by alias and a later operand stores it/,
        "names the cause: $src";
}

# A FIRST STORE IS TAKEN FOR THE DECLARATION. When its value reads the
# variable it declares, `my $u = (($u // "") . "z")` names a $u that does not
# exist yet, and the program does not compile.
round_trips($_) for
    'use v5.36; my $u; my $r = \$u; $u .= "z"; print "ok\n";',
    'use v5.36; sub k { my $u; my $r = \$u; $u .= "z"; 1 } print k(), "\n";',
    'use v5.36; my $u; my $r = \$u; $u .= "z"; $u = "q"; print "$$r\n";',
    'use v5.36; my ($u, $w); my $r = \$u; $u .= "z"; print "$$r\n";',
    'use v5.36; my $u; my $r = \$u; $u .= "z"; print "$$r\n";',
    'use v5.36; my $u; my $r = \$u; $u .= "z" . ref($r); print "$$r\n";',
    'use v5.36; my $u; my $f = sub { $u }; $u .= "z"; print $f->(), "\n";';

# A STORE'S RESULT IS THE VARIABLE, not a copy: a later operand that stores
# it again shows through. perl prints `abcabc`; the snapshot printed `ababc`.
refuses($_) for
    'use v5.36; my $s = "a"; my $f = sub { print(($s .= "b"), ($s .= "c"), "\n") }; $f->();',
    'use v5.36; my $s = "a"; my $f = sub { my @x = ($s .= "b", $s .= "c"); print "@x\n" }; $f->();',
    'use v5.36; my $s = "a"; my $r = \$s; my @x = ($s .= "b", $s .= "c"); print "@x\n";',
    'use v5.36; my $s = "a"; sub foo { print "@_\n" } my $f = sub { foo($s .= "b", $s .= "c") }; $f->();',
    'use v5.36; my $s = "a"; my $r = \$s; my @x = ($s .= "b", $s = "z"); print "@x\n";',
    'use v5.36; my $s = "a"; my @x = ($s .= "b", $s .= "c"); print "@x\n";',
    'use v5.36; my $s = "a"; my $r = \$s; my @x = ($s = "b", $s = "c"); print "@x\n";',
    'use v5.36; my $s = "a"; my $f = sub { my $v = ($s .= "b") . ($s .= "c"); print "$v\n" }; $f->();',
    'use v5.36; my $s = 1; my $r = \$s; my @x = ($s = $s + 1, $s = 5); print "@x\n";',
    'use v5.36; my $s = "a"; my @x = ($s = "b", $s = "c"); print "@x\n";';

# ONE STORE RESULT ALONE is still its value.
round_trips($_) for
    'use v5.36; my $s = "a"; my $f = sub { print(($s .= "b"), "\n") }; $f->();',
    'use v5.36; my $s = "a"; my $r = \$s; my @x = ($s .= "b", "c"); print "@x\n";',
    'use v5.36; my $s = "a"; my $r = \$s; my $v = ($s .= "b") . "c"; print "$v\n";';

done_testing;
