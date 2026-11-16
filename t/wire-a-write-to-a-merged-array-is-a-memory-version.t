# ABOUTME: push, unshift, splice, shift, pop on an array merged as versions (`@p = ()` in an arm or a
# ABOUTME: loop) change it in place: each takes the memory it runs at, is the version after, and merges.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub graph ($src, $sub) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
    return { map { $_->{id} => $_ } @{ $j->{methods}{$sub}{nodes} // [] } };
}
sub calls ($n, $name) { grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq $name } values %$n }
# reaches($n, $from, $to): memory version $to is $from or reached back from it
sub reaches ($n, $from, $to) {
    my %seen; my @q = ($from);
    while (defined(my $id = shift @q)) {
        return 1 if $id == $to;
        next if $seen{$id}++;
        my $x = $n->{$id} or next;
        push @q, $x->{op} eq 'Phi' ? @{ $x->{inputs} } : $x->{inputs}[-1] // ();
    }
    return 0;
}

# pvm c140: `@p` reset in an arm of the loop body is a merge of versions at the
# loop's head; the push onto it changes the version the way taken holds.
my $c140 = q{sub f { my @p; my $out = ""; for my $pos (0 .. 5) { push @p, $pos if $pos % 2; if (@p > 1) { for my $s (@p) { $out .= $s } $out .= "|"; @p = (); } } return "$out @p" } print f(), "\n";};
{
    my $n = graph($c140, 'main::f');
    my ($push) = calls($n, 'push');
    ok($push, 'the push is there');
    ok($push->{fields}{memory_input}, 'it takes the memory it runs at');
    is(( $n->{ $push->{inputs}[0] }{op} // '' ), 'Phi', 'of the merge of the array');
    ok(defined $push->{control_in}, 'where it stands');
    my ($count) = grep { $_->{op} eq 'Count' && $_->{inputs}[0] == $push->{inputs}[0] } values %$n;
    ok($count && reaches($n, $count->{inputs}[1], $push->{id}), 'the count after it reads at a memory after it');
    my ($loopmem) = grep { $_->{op} eq 'Phi' && $_->{fields}{memory} && ( $n->{ $_->{fields}{region} }{op} // '' ) eq 'Loop' } values %$n;
    ok($loopmem && reaches($n, $loopmem->{inputs}[1], $push->{id}), "and the loop's memory merges it round the back edge");
}
for my $op ([unshift => 'unshift @p, $pos'], [splice => 'splice(@p, 0, 0, $pos)'], [pop => 'pop @p'], [shift => 'shift @p']) {
    my ($name, $stmt) = @$op;
    my $n = graph(qq{sub f { my \@p; my \$o = ""; for my \$pos (0 .. 5) { $stmt if \$pos % 2; \$o .= scalar(\@p); if (\@p > 3 || !\@p) { \@p = (7); } } return "\$o \@p" } print f(), "\\n";}, 'main::f');
    my ($c) = calls($n, $name);
    ok($c && $c->{fields}{memory_input} && ( $n->{ $c->{inputs}[0] }{op} // '' ) eq 'Phi', "$name onto the merge takes its memory");
}
{   # (a merge at an if, not a loop: the same)
    my $n = graph(q{sub f { my ($c) = @_; my @p = (1); if ($c) { @p = (5, 6) } else { @p = (2) } push @p, 9; scalar(@p) } print f(0), f(1), "\n";}, 'main::f');
    my ($push) = calls($n, 'push');
    ok($push && $push->{fields}{memory_input}, 'a push onto a merge at an if');
}
{   # (not a scalar merged from two references: that is no array)
    my $n = graph(q{sub f { my ($c) = @_; my $r = $c ? [1] : [2]; my $k = ref($r); $k } print f(1), "\n";}, 'main::f');
    my ($ref) = calls($n, 'ref');
    ok(!$ref || !$ref->{fields}{memory_input}, 'a merge of array references is not an array');
}
done_testing;
