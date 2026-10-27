# ABOUTME: an explicit `return` leaves every scope a `local` element store is in: the
# ABOUTME: element is put back (ElemRestore) before the exit, as a fall-through end does.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src, $sub) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return decode_json($out)->{methods}{$sub}{nodes};
}

# The restore was made at a block's end and the sub's, never at a return:
# `local $self->{c} = ...; return h($self)` kept the store (pvm 176).
# EVERY PATH OUT puts it back: the return's, and the end's (when there is one).
for my $c (
    [ 1,     q{my %h = (a => 1); sub f { local $h{a} = 2; return $h{a} } print f(), $h{a}, "\n";},
    ],
    [ 2,     q{my %h = (a => 1); sub f { local $h{a} = 2; if ($_[0]) { return 7 } $h{a} } print f(1), f(0), $h{a}, "\n";},
    ],
    [ 2,     q{my %h = (a => 1); sub f { local $h{a} = 2; for my $i (1 .. 3) { return $i if $i == 2 } 0 } print f(), $h{a}, "\n";},
    ],
) {
    my ($want, $src) = @$c;
    my @n = graph_of($src, 'main::f')->@*;
    my @restores = grep { $_->{op} eq 'ElemRestore' } @n;
    is(scalar(@restores), $want, "a restore on each way out ($want): $src");
}

# Without a local, no restore is made.
my @n = graph_of(q{my %h = (a => 1); sub f { return $h{a} } print f(), "\n";}, 'main::f')->@*;
ok(!grep({ $_->{op} eq 'ElemRestore' } @n), 'no local, no restore');

done_testing;
