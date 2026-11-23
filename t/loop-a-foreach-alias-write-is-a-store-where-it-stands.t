# ABOUTME: A write to a foreach's alias is a store to the element where it stands, as perl's alias is
# ABOUTME: the element: a pass left by last, return or a label keeps it, and a callee reads it mid-pass.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub write_src ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub run_perl ($f) { return scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null) }

# The wire, deparsed, runs as perl does. Not refused: each of these lowered
# before (to a wrong answer), and the store at the write must keep it lowered.
sub round_trips ( $src, $name ) {
    my $f    = write_src($src);
    my $want = run_perl($f);
    my $j    = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die;
    my $err = do { local $/; <$e> } =~ s/^\S+ syntax OK\n//mr;
    is $err, '', "$name: the producer says nothing" or return;
    my $d   = SoN::Deparse->new;
    my $out = $d->render( JSON::PP->new->decode($j) );
    ok defined $out, "$name: deparsed" or return diag $d->gap;
    is run_perl( write_src($out) ), $want, "$name: runs as perl does"
        or diag "--- emitted ---\n$out";
}

# WHY: the write was stored back at the end of the pass, which a pass left
# early never reaches: `last if` after `$e .= "x"` printed `1 2` for perl's
# `1x 2` (a silent wrong answer since the write-back was made).
round_trips( q{my @a=(1,2); for my $e (@a) { $e .= "x"; last if $e eq "1x" } print "@a\n";},
    'a named alias, then last if' );
round_trips( q{my @a=(1,2); for (@a) { $_ .= "x"; last if $_ eq "1x" } print "@a\n";},
    '$_, then last if' );
round_trips( q{my @a=(1,2); for my $e (@a) { $e .= "x"; if ($e eq "1x") { last } } print "@a\n";},
    'a last in an arm' );
# (a named iterator: the deparser refuses a `$_` a sub saves and stores in a
# loop, as it did before this; chalk's probes take that form)
round_trips( q{my @a=(1,2); sub f { for my $e (@a) { $e .= "x"; return if $e eq "1x" } } f(); print "@a\n";},
    'a return out of the pass' );
round_trips( q{my @a=(1,2); OUT: for my $i (1..2) { for (@a) { $_ .= "x"; next OUT if $i == 1 } } print "@a\n";},
    'a next naming the outer loop' );
round_trips( q{my @a=(1,2); OUT: for my $i (1..2) { for my $e (@a) { $e .= "x"; last OUT if $i == 1 } } print "@a\n";},
    'a last naming the outer loop' );
round_trips( q{my @a=(1,2); my @r; OUT: for my $i (1..3) { push @r, join(",", @a); for (@a) { $_ .= "x"; next OUT if $i == 2 } } print "@r\n";},
    'lw60: the outer read on the next pass' );
round_trips( q{my @a=(1,2); for my $e (@a) { $e .= "x"; next if $e eq "1x"; $e .= "y" } print "@a\n";},
    'a next (kept)' );

# A CALLEE WRITES THE ALIAS (`$_[0]`), and the write is the call: the
# iterator's slot is stored to the element after it, not at the pass end.
round_trips( q{sub b { $_[0] .= "x" } my @a=(1,2); for my $e (@a) { b($e); last if $e eq "1x" } print "@a\n";},
    'a callee writes it, then last if' );

# A CALLEE READS THE ARRAY MID-PASS, and perl's alias has already written the
# element: `1 2;1x 2;` for perl's `1x 2;1x 2x;`.
round_trips( q{my @a=(1,2); my $s=""; sub show { $s .= "@a;" } for my $e (@a) { $e .= "x"; show() } print "$s\n";},
    'a callee reads the array after the write' );
round_trips( q{my @a=(1,2); my $s=""; sub show { $s .= join(",", @a) . ";" } for my $e (@a) { $e .= "x"; show(); last if $e eq "2x" } print "$s @a\n";},
    'a callee reads it, then last if' );

# AN IF/ELSE WRITING THE ALIAS IN BOTH ARMS stores in each, so it needs real
# arms: as a select, the stores hung off the control before it.
round_trips( q{my @a=(1,2); for my $e (@a) { if ($e == 1) { $e = 10 } else { $e = 20 } last if $e == 10 } print "@a\n";},
    'an if/else writing the alias' );
round_trips( q{my @a=(1,2); for (@a) { if ($_ == 1) { $_ = 10 } else { $_ = 20 } last if $_ == 10 } print "@a\n";},
    'an if/else writing $_' );

# A WRITE THROUGH `my $r = \$x` reaches the element by the pass-end copy of
# the iterator's slot, which a pass left early never reaches (`1 2` for perl's
# `1x 2`): refused by name, until a reference to the iterator is one to the
# element.
subtest 'a reference to the iterator in a pass left early is refused by name' => sub {
    my $f = write_src(q{my @a=(1,2); for my $x (@a) { my $r = \$x; $$r .= "x"; last if $$r eq "1x" } print "@a\n";});
    my $err = qx($^X -Ilib -MO=-q,SoN,json $f 2>&1 >/dev/null);
    like $err, qr/GAP: a reference to a foreach iterator in a pass that may be left early/, 'refused by name';
    my $ok = write_src(q{my @a=(1,2); for my $x (@a) { my $r = \$x; $$r .= "x" } print "@a\n";});
    round_trips( do { open my $h, '<', $ok or die; local $/; <$h> }, 'the same with no early exit (lowered)' );
};

# THE ELEMENT CHANGED BY ANOTHER WAY after the alias is written -- an element
# store, a store through a reference, a callee closing over the array -- is
# what a read of the alias then sees in perl; the walk reads its own binding
# (`1y2y` for perl's `q2y`). Refused by name, as a reshape or a call over a
# list a callee reaches already was.
subtest 'the element changed by another way after an alias write is refused by name' => sub {
    for my $src (
        q{sub f { my @a = (1,2); my $s=""; for my $x (@a) { $x .= "y"; $a[0] = "q"; $s .= $x } print "$s|@a\n" } f();},
        q{sub f { my @a = (1,2); my $r = \@a; my $s=""; for my $x (@a) { $x .= "y"; $r->[0] = "q"; $s .= $x } print "$s|@a\n" } f();},
        q{my @a=(1,2); my $s=""; sub w { $a[0] = "q" } for my $x (@a) { $x .= "y"; w(); $s .= $x } print "$s|@a\n";},
    ) {
        my $f   = write_src($src);
        my $err = qx($^X -Ilib -MO=-q,SoN,json $f 2>&1 >/dev/null);
        like $err, qr/GAP: a foreach whose body writes its alias and may /, 'refused by name';
    }
};

done_testing;
