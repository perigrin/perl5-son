# ABOUTME: A whole-aggregate assignment in a branch arm, in a loop or straight-line, round
# ABOUTME: trips: each assigned version is its own variable and an array merge stays an array.

use v5.42.0;
use Test2::V0;
use JSON::PP;
# ABOUTME: A whole-aggregate assignment in a branch arm, in a loop or straight-line, round
# ABOUTME: trips: each assigned version is its own variable and an array merge stays an array.

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

# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}

my @cases = (
    [ q{my @e; for my $k (0,1) { if ($k) { @e = (0,4) } else { @e = (9) } } print "@e\n";},
      'both arms assign @e in a loop' ],
    [ q{my $k = shift // 1; my @e; if ($k) { @e = (0,4) } else { @e = (9) } print "@e\n";},
      'both arms assign @e, straight line' ],
    [ q{sub f { my @e; for my $k (@_) { if ($k) { @e = (0,4) } else { @e = (9) } } return "@e" } print f(0,1), "\n"; print f(1,0), "\n";},
      'both arms assign @e in a sub' ],
    [ q{my @e; for my $k (0,1) { if ($k) { @e = (0,4) } } print "@e\n";},
      'one arm assigns @e in a loop' ],
    [ q{my @e; for my $k (0,1) { if ($k) { @e = (0,4) } else { @e = (9) } } print scalar(@e), "\n";},
      'the merged @e in scalar context' ],
    [ q{my (@e, @f); for my $k (0,1) { if ($k) { @e = (0,4) } else { @f = (9) } } print "@e|@f\n";},
      'each arm assigns a different array' ],
    [ q{my @e = (1); print "@e\n"; @e = (2,3); print "@e\n";},
      'a straight-line reassignment' ],
    [ q{my @e = (7); for my $k (0,1) { if ($k) { @e = (0,4) } else { @e = (9) } } print "$e[0] $#e\n";},
      'an element and the last index of the merged @e' ],
    [ q{my %h; for my $k (0,1) { if ($k) { %h = (a => 1) } else { %h = (b => 2) } } print join(",", sort keys %h), "\n";},
      'both arms assign %h in a loop' ],
    [ q{my @e = (1); my $k = shift // 1; if ($k) { @e = (0,4) } print "@e ", scalar(@e), "\n";},
      'one arm reassigns @e, straight line' ],
    [ q{my @e = (1); print "$e[0]\n"; @e = (2,3); print "$e[1] @e[0,1]\n";},
      'an element and a slice of each version' ],
);

for my $c (@cases) {
    round_trips(@$c);
    emits_quietly(@$c);
}

# A REFERENCE SEES EVERY VERSION. `\@e` is one container whatever is later
# assigned into it, and a version per assignment cannot say so -- the
# reference kept the first contents (perl `2 3`, emitted `1`). Refused until
# the container is modelled as storage.
for my $src (
    q{my @e = (1); my $r = \@e; @e = (2,3); print "@$r\n";},
    q{my @e; my $r = \@e; for my $k (0,1) { if ($k) { @e = (0,4) } else { @e = (9) } } print "@$r\n";},
    # Taken under a branch, the reference is lowered out of execution order,
    # so where it stands against the assign is not known: refused.
    q{my @e = (1); my $r; my $k = shift // 1; if ($k) { $r = \@e } @e = (2); print "@$r\n";},
    q{my @e = (1); my $k = shift // 0; if ($k) { my $r = \@e; print "@$r\n" } else { @e = (2) } print "@e\n";},
    # In a loop, a reference taken later in the body reaches the next pass.
    q{my @e; for my $k (0,1) { @e = ($k); my $r = \@e; print "@$r\n" }},
) {
    graph_of($src);
    like producer_stderr(),
        qr/GAP: a whole assign to a pad aggregate a reference was taken to/,
        "refused: $src";
}

# A REFERENCE TAKEN AFTER THE LAST ASSIGN sees only that version, so nothing
# is refused there: the assigns before it are versions no reference reaches.
for my $c (
    [ q{my @e = (1); @e = (2); my $r = \@e; print "@$r\n";},
      'a reference taken after the last whole assign' ],
    [ q{my %h = (a => 1); %h = (b => 2); my $r = \%h; print join(",", keys %$r), "\n";},
      'a hash reference taken after the last whole assign' ],
) {
    round_trips(@$c);
}

done_testing;
