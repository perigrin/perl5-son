# ABOUTME: an anon sub captures the variable perl closes over (its pad entry's parent index), not the
# ABOUTME: first of that name: `my $i = 1; { my $i = 5; sub { $i = 7 } }` writes the inner one.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

sub json_of ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
}
sub nodes ($j, $sub = 'main::__PROGRAM__') { return { map { $_->{id} => $_ } @{ $j->{methods}{$sub}{nodes} // [] } } }
sub perl_out ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return scalar qx($^X $pl 2>&1);
}

my $shadow = q{my $i = 1; { my $i = 5; my $f = sub { $i = 7 }; $f->(); print "$i\n" } print "$i\n";};
{   my $n = nodes(json_of($shadow));
    my ($cell) = grep { $_->{op} eq 'MakeCell' } values %$n;
    # (the variable is kept in memory: the store before the cell is made is its value)
    my $st = $cell && $n->{ $cell->{mem_in} // -1 };
    is($st && $st->{op} eq 'Assign' && $n->{ $st->{inputs}[1] }{fields}{value}, 5, "the cell is the inner \$i's, the one the closure closes over");
    is($st && '$' . $n->{ $st->{inputs}[0] }{fields}{symbol}, $cell->{fields}{cell_name}, 'and named as it is');
}
my $two = q{my $x = 1; my $g = sub { $x }; { my $x = 2; my $f = sub { $x }; print $f->(), $g->(), "\n" }};
{   my $j = json_of($two);
    my $n = nodes($j);
    my @cells = sort map { $_->{fields}{cell_name} } grep { $_->{op} eq 'MakeCell' } values %$n;
    is(scalar @cells, 2, 'two closures over two `$x`s: two cells');
    isnt($cells[0], $cells[1], 'named apart, as the program spells the two variables');
    my %spelled = map { ( $_->{fields}{symbol} => 1 ) } grep { $_->{op} eq 'PadAccess' && $_->{fields}{sigil} eq '$' } values %$n;
    ok(!grep({ !$spelled{ substr($_, 1) } } @cells), 'each named as its variable is');
    my @params = sort map { $_->{fields}{name} } grep { $_->{op} eq 'CellParam' } map { values %{ nodes($j, $_) } } grep { /__ANON__/ } keys %{ $j->{methods} };
    is_deeply(\@params, \@cells, "and each body's cell parameter so");
}
# THE ROUND TRIP: the graph rendered back to Perl prints what perl does.
for my $src ($shadow, $two, q{my @a = (5); my $f = sub { "@a" }; my @a = (1); push @a, 2; print $f->(), "/", "@a", "\n";}) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(json_of($src));
    ok(defined $out, 'renders') or diag $d->gap;
    is(perl_out($out // ''), perl_out($src), 'as perl: ' . substr($src, 0, 40));
}
done_testing;
