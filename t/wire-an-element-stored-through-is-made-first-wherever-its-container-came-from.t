# ABOUTME: `$self->{t}{$k} = v`, `push @{ $s->{l} }, v`: the element dereferenced for a write is made a
# ABOUTME: hash or array first (`//= {}`) whether the outer hash is a `my` one, just made, or an argument's.
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
sub vivified ($n, $kind) {
    grep {
        my $v = $n->{ $_->{inputs}[1] } // {};
        $_->{op} eq 'Assign' && $v->{op} eq 'DefinedOr' && ( $n->{ $v->{inputs}[1] }{op} // '' ) eq $kind
            && defined $_->{control_in}
    } values %$n;
}

for my $case (
    [ q{sub f { my ($s, $k) = @_; $s->{t}{$k} = 1; return } my $s = {}; f($s, "a"); print join(",", keys %{$s->{t}}), "\n";}, 'HashLiteral', 'a hash two down an argument (pvm c175)' ],
    [ q{sub f { my ($s) = @_; push @{$s->{l}}, 1; return } my $s = {}; f($s); print "@{$s->{l}}\n";}, 'ArrayLiteral', 'a push onto an array an argument\'s element holds' ],
    [ q{sub f { my ($s, @k) = @_; $s->{t}{$_} = 1 for @k; return } my $s = {}; f($s, "a"); print keys %{$s->{t}}, "\n";}, 'HashLiteral', 'in a loop body (pvm c224)' ],
    [ q{my %h; for my $i (1 .. 2) { $h{$i % 2}{$i} = 1 } print scalar(keys %h), "\n";}, 'HashLiteral', "a `my` hash's element in a loop body" ],
) {
    my ($src, $kind, $name) = @$case;
    my $n = graph($src, $src =~ /\Asub f/ ? 'main::f' : 'main::__PROGRAM__');
    ok(scalar(vivified($n, $kind)) >= 1, "$name: made first, where it stands");
}
{   # THE READ IT MAKES IS ITS OWN: one of the same element at the same memory
    # (the condition's) stays where it was, not in the arm the store is in.
    my $n = graph(q{my %h = (a => [1]); my @o = map { ref $h{$_} eq 'HASH' ? join("", sort keys %{$h{$_}}) : "@{$h{$_}}" } sort keys %h; print "@o\n";});
    my ($rt) = grep { $_->{op} eq 'RefType' } values %$n;
    my $read = $rt && $n->{ $rt->{inputs}[0] };
    ok($read && !defined $read->{control_in}, "the condition's read is not the vivify's");
}
done_testing;
