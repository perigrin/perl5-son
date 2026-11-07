# ABOUTME: `%h = (...)` / `@a = (...)` on a tied aggregate is a store INTO it (perl calls
# ABOUTME: CLEAR and STORE), not a new value: the variable keeps naming its container.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub graph ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json $pl 2>&1 >/dev/null);
    my $j = eval { decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null)) } // {};
    my %n;
    my $walk; $walk = sub ($x) {
        if (ref $x eq 'HASH') { $n{ $x->{id} } = $x if defined $x->{op} && defined $x->{id} && !ref $x->{id}; $walk->($_) for values %$x }
        elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
    };
    $walk->($j->{methods}{'main::__PROGRAM__'} // {});
    return (\%n, $err);
}
for my $c (
    [ q{package TH; sub TIEHASH { bless {}, shift } sub CLEAR { 1 } sub STORE { 1 } sub FETCH { 1 } package main; my %h; tie %h, "TH"; %h = (x => 1); print $h{x}, "\n";}, '%', 'a tied hash' ],
    [ q{package TA; sub TIEARRAY { bless {}, shift } sub CLEAR { 1 } sub STORE { 1 } sub FETCH { 1 } sub FETCHSIZE { 1 } sub EXTEND { 1 } package main; my @a; tie @a, "TA"; @a = (1, 2); print $a[0], "\n";}, '@', 'a tied array' ],
) {
    my ($src, $sig, $name) = @$c;
    my ($n, $err) = graph($src);
    unlike($err, qr/GAP|skipped/, "$name: not refused");
    my ($tie) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'tie' } values %$n;
    my ($st) = grep { $_->{op} eq 'Assign' && $tie && $_->{inputs}[0] == $tie->{inputs}[0] } values %$n;
    ok($st, "$name: the assign stores into the container the tie named");
    my ($read) = grep { $_->{op} eq 'Subscript' && defined $_->{control_in} } values %$n;
    is($read && $read->{inputs}[0], $tie && $tie->{inputs}[0], "$name: a later read is of that container");
}
done_testing;
