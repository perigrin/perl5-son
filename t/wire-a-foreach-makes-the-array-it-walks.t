# ABOUTME: `for (@{ $h{k} })` makes the element an array when it is undef, as perl's foreach does
# ABOUTME: (its list is an lvalue): spelled `$h{k} //= []` where it stands, as for map and grep.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub graph ($src, $sub = 'main::__PROGRAM__') {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
    return { map { $_->{id} => $_ } @{ $j->{methods}{$sub}{nodes} // [] } };
}
# vivified($n, $kind) -> the stores `elem //= []` (or `{}`) in the graph
sub vivified ($n, $kind = 'ArrayLiteral') {
    grep {
        my $v = $n->{ $_->{inputs}[1] } // {};
        $_->{op} eq 'Assign' && $v->{op} eq 'DefinedOr' && ( $n->{ $v->{inputs}[1] }{op} // '' ) eq $kind
            && defined $_->{control_in}
    } values %$n;
}
# walks($n, $assign) -> a deref of the vivified value is what the loop walks
sub walks ($n, $a) {
    my $viv = $n->{ $a->{inputs}[1] }{id};
    grep { $_->{op} eq 'PostfixDeref' && $_->{inputs}[0] == $viv } values %$n;
}

for my $case (
    [ q{my %h; for my $e (@{$h{x}}) { print $e } print exists $h{x} ? "viv\n" : "no\n";}, undef, "a `my` hash's element" ],
    [ q{my %in = (a => [1]); for my $d (qw(a b)) { for my $i ($in{$d}->@*) { print $i } }}, undef, 'in a loop body (pvm c124)' ],
    [ q{sub f { my ($n) = @_; my $c = 0; for my $k ($n->{kids}->@*) { $c++ } $c } print f({}), "\n";}, 'main::f', 'through a reference an argument holds (pvm c135)' ],
    [ q{sub f { my ($r) = @_; my $c = 0; for my $k (@{$r->[1]}) { $c++ } $c } print f([]), "\n";}, 'main::f', "an array reference's element" ],
    [ q{my %h; my @m = map { $_ } @{$h{x}}; print exists $h{x} ? "viv\n" : "no\n";}, undef, 'as map does (the same root)' ],
) {
    my ($src, $sub, $name) = @$case;
    my $n = graph($src, $sub // 'main::__PROGRAM__');
    my @v = vivified($n);
    is(scalar @v, 1, "$name: the element is made an array where it stands");
    ok(@v && walks($n, $v[0]), "$name: and the loop walks that array");
}
{   # (a foreach over a `my` array, or a list, makes nothing)
    my $n = graph(q{my @a = (1); for my $e (@a) { print $e } print "\n";});
    is(scalar(vivified($n)), 0, 'a foreach over a `my` array makes nothing');
}
done_testing;
