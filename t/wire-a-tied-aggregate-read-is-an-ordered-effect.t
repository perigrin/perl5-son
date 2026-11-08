# ABOUTME: every read of a tied array or hash is a method call (FETCH, FETCHSIZE, ...)
# ABOUTME: that may change anything: on the control chain, a memory version of its own.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub graph ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json $pl 2>&1 >/dev/null);
    my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
    my %n;
    my $walk; $walk = sub ($x) {
        if (ref $x eq 'HASH') { $n{ $x->{id} } = $x if defined $x->{op} && defined $x->{id} && !ref $x->{id}; $walk->($_) for values %$x }
        elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
    };
    $walk->($j->{methods}{'main::__PROGRAM__'} // {});
    return (\%n, $err);
}
my $TA = q{package TA; sub TIEARRAY { bless {}, shift } sub FETCH { "e" } sub FETCHSIZE { 2 } package main; };

{   # two reads of one element are two FETCHes, each after the last
    my ($n) = graph($TA . q{my @a; tie @a, "TA"; my $x = $a[0]; my $y = $a[0]; print "$x$y\n";});
    my @reads = grep { $_->{op} eq 'Subscript' } values %$n;
    is(scalar @reads, 2, 'two reads of one element of a tied array are two nodes');
    ok(!( grep { !defined $_->{control_in} } @reads ), 'each on the control chain');
}
{   # a count in a loop over a tied array is made each pass: in the loop, after the memory phi
    my ($n) = graph($TA . q{my @a; tie @a, "TA"; for my $e (@a) { print $e } print "\n";});
    my ($count) = grep { $_->{op} eq 'Count' } values %$n;
    my $mem = $count ? $n->{ $count->{inputs}[1] } : undef;
    ok($mem && $mem->{op} eq 'Phi', 'the loop\'s count of a tied array reads the loop\'s memory phi');
    is(scalar( grep { $_->{op} eq 'Count' } values %$n ), 1, 'and is not also made once before the loop');
}
{   # a package scalar a tie method writes is read after the methods ran
    my ($n) = graph($TA . q{my @a; tie @a, "TA"; my $x = $a[0]; print "$main::L\n";});
    my ($read) = grep { $_->{op} eq 'Subscript' } values %$n;
    my ($l) = grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq 'L' } values %$n;
    is($l->{inputs}[0], $read->{id}, 'a later package read is at the FETCH\'s memory version');
}
{   # a whole assign to a tied hash is a store into it (CLEAR and STOREs), not refused --
    # see wire-a-whole-assign-to-a-tied-aggregate-is-in-place.t
    my (undef, $err) = graph(q{package TH; sub TIEHASH { bless {}, shift } package main; my %h; tie %h, "TH"; %h = (x => 1); print "ok\n";});
    unlike($err, qr/GAP|skipped/, 'a list assigned to a tied hash is translated, in place');
}
{   # a read in a short-circuit arm is on the arm's control chain too (as a ternary's is)
    for my $op (q{&&}, q{||}, q{//}) {
        my ($n) = graph($TA . qq{my \@a; tie \@a, "TA"; my \$c = shift; my \$x = \$c $op \$a[0]; print "\$x\\n";});
        my @reads = grep { $_->{op} eq 'Subscript' } values %$n;
        is(scalar @reads, 1, "one read in the $op arm");
        ok(@reads && defined $reads[0]{control_in}, "it is on the control chain ($op)");
    }
}
done_testing;
