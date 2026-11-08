# ABOUTME: a read through a reference ($r->{k}, $r->[i], $$r) may die -- no HASH, ARRAY or SCALAR
# ABOUTME: reference there -- so it is on the control chain where it stands, as a may-die divide is.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub graph ($src, $sub = 'main::__PROGRAM__') {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
    my %n;
    my $walk; $walk = sub ($x) {
        if (ref $x eq 'HASH') { $n{ $x->{id} } = $x if defined $x->{op} && defined $x->{id} && !ref $x->{id}; $walk->($_) for values %$x }
        elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
    };
    $walk->($j->{methods}{$sub} // {});
    return \%n;
}
sub reads ($n, $op) { grep { $_->{op} eq $op } values %$n }

{   my $n = graph(q{sub f { my $s = shift; my $v = $s->{a}; $main::L = "x"; $v } print f({a => 1}), "\n";}, 'main::f');
    my @r = reads($n, 'Subscript');
    is(scalar @r, 1, 'one hash element read through a reference');
    ok(@r && defined $r[0]{control_in}, 'on the control chain');
}
{   my $n = graph(q{sub g { my $r = shift; my $v = $r->[1]; $v } print g([1, 2]), "\n";}, 'main::g');
    my @r = reads($n, 'Subscript');
    ok(@r && !grep({ !defined $_->{control_in} } @r), 'an array element through a reference too');
}
{   my $n = graph(q{my %h = (a => 1); my $v = $h{a}; print "$v\n";});
    my @r = reads($n, 'Subscript');
    ok(@r && !grep({ defined $_->{control_in} } @r), 'a `my %h` element is not: it cannot die');
}
{   my $n = graph(q{my $x = 1; my $r = \$x; my $v = $$r; print "$v\n";});
    my @r = grep { ( $_->{fields}{sigil} // '' ) eq '$' } reads($n, 'PostfixDeref');
    ok(@r && defined $r[0]{control_in}, 'a scalar deref is on the chain');
}
done_testing;
