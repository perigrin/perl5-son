# ABOUTME: a read through a reference ($r->{k}, $r->[i], %$r, @$r, exists $r->{k}) may die -- no
# ABOUTME: HASH or ARRAY reference there -- so it is on the control chain and memory where it stands.
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
sub reads ($n, $op, $sigil = undef) {
    grep { $_->{op} eq $op && ( !defined $sigil || ( $_->{fields}{sigil} // '' ) eq $sigil ) } values %$n;
}
sub pinned (@r) { @r && !grep { !defined $_->{control_in} } @r }

{   my $n = graph(q{sub f { my $s = shift; my $v = $s->{a}; $main::L = "x"; $v } print f({a => 1}), "\n";}, 'main::f');
    my @r = reads($n, 'Subscript');
    is(scalar @r, 1, 'one hash element read through a reference');
    ok(pinned(@r), 'on the control chain');
}
{   my $n = graph(q{sub g { my $r = shift; my $v = $r->[1]; $v } print g([1, 2]), "\n";}, 'main::g');
    ok(pinned(reads($n, 'Subscript')), 'an array element through a reference too');
}
{   my $n = graph(q{sub f { my $r = [[1, 2]]; my $v = $r->[0][1]; $r->[0][1] = 9; $v } print f(), "\n";}, 'main::f');
    # (the element it is through is vivified first, audit 2026-11-22 W9: a
    # read of `$r->[0] // []`, a DefinedOr)
    my @r = grep { ( $n->{ $_->{inputs}[0] }{op} // '' ) =~ /\A(?:Subscript|DefinedOr)\z/ && defined $_->{mem_in} } reads($n, 'Subscript');
    ok(pinned(@r), 'an element through an element holding a reference');
}
{   my $n = graph(q{sub f { my ($h) = @_; my $k = join ",", sort keys %$h; $h->{b} = 2; $k } print f({a => 1}), "\n";}, 'main::f');
    ok(pinned(reads($n, 'PostfixDeref', '%')), 'a whole hash through a reference (keys %$h)');
}
{   my $n = graph(q{sub f { my ($r) = @_; my $c = @$r; push @$r, 1; $c } print f([1]), "\n";}, 'main::f');
    ok(pinned(grep { my $d = $_; grep { $_->{op} eq 'Count' && $_->{inputs}[0] == $d->{id} } values %$n } reads($n, 'PostfixDeref', '@')),
       'a whole array through a reference (@$r)');
}
{   my $n = graph(q{sub f { my ($v) = @_; if (ref($v) eq 'HASH') { print exists $v->{a} ? 1 : 0, "\n" } } f({a => 1});}, 'main::f');
    ok(pinned(reads($n, 'Exists')), 'an exists through a reference, in an arm');
}
{   my $n = graph(q{my %h = (a => 1); my $v = $h{a}; print "$v\n";});
    my @r = reads($n, 'Subscript');
    ok(@r && !grep({ defined $_->{control_in} } @r), 'a `my %h` element is not: it cannot die');
}
{   my $n = graph(q{sub f { my $h = {a => 1}; my @k = keys %$h; $h->{b} = 2; "@k" } print f(), "\n";}, 'main::f');
    my @r = reads($n, 'PostfixDeref', '%');
    ok(@r && !grep({ defined $_->{control_in} } @r), 'nor a fresh {...}: it is a hash reference');
}
{   my $n = graph(q{sub f { my ($r) = @_; my $v = $$r; $$r = 2; $v } my $x = 1; print f(\$x), "\n";}, 'main::f');
    ok(pinned(grep { defined $_->{mem_in} } reads($n, q(PostfixDeref), q($))), 'a scalar deref is on the chain');
}
{   my $n = graph(q{my $x = 1; my $r = \$x; my $v = $$r; print "$v\n";});
    my @r = reads($n, 'PostfixDeref', '$');
    ok(@r && !grep({ defined $_->{control_in} } @r), 'not one of a reference just made: it cannot die');
}
{   my $n = graph(q{sub f { my ($k, $r) = @_; if ($k) { print $$r, "\n" } else { print $$r + 1, "\n" } } f(1, \2); f(0, \2);}, 'main::f');
    my @r = grep { defined $_->{mem_in} } reads($n, q(PostfixDeref), q($));
    ok(@r == 2 && pinned(@r), 'one read in each arm, each pinned in its own');
}
{   my $n = graph(q{sub f { my @s; for my $v (@_) { if (ref($v) eq 'ARRAY') { } elsif (ref($v) eq 'HASH' && exists $v->{a}) { push @s, $v } } scalar @s } print f({ a => 1 }, [2], { b => 1 }), "\n";}, 'main::f');
    my %succ;
    $succ{ $_->{control_in} }++ for grep { defined $_->{control_in} } values %$n;
    ok(pinned(reads($n, 'Exists')), 'an exists through a reference in a short-circuit arm');
    is(scalar(grep { $_ > 1 } values %succ), 0, 'and its arm merges control: no node has two successors');
}
done_testing;
