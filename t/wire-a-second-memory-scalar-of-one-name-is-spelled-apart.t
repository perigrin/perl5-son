# ABOUTME: Two `my $x` of one name in one sub, each kept in memory (handed to
# ABOUTME: a call), are two variables: the second is spelled apart on the wire.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub scalar_symbols ($data, $graph) {
    my %s;
    for my $n ($data->{methods}{$graph}{nodes}->@*) {
        next unless $n->{op} eq 'PadAccess' && ($n->{fields}{sigil} // '') eq '$';
        $s{ $n->{fields}{symbol} } = 1;
    }
    return [ sort keys %s ];
}

# A SCALAR HANDED TO A CALL IS A LOCATION, not an SSA value -- `@_` aliases
# it -- so its reads and writes go through memory, and a PadAccess names it
# by its symbol alone. An inner `my $x` shadowing an outer one reached the
# wire as the same `$x`: a consumer that keys the location by name (chalk's
# LLVM backend) made one variable of the two, and the outer read after the
# block saw the inner's 2 (l1l2l2 for perl's l1l2l1).
my $src = <<'SRC';
sub ld { "l" . $_[0] }
my $x = 1; print ld($x);
{ my $x = 2; print ld($x); }
print ld($x), "\n";
SRC

my $data = graph_of($src);
is scalar_symbols($data, 'main::__PROGRAM__'), [ 'x', 'x__2' ],
    'the shadowing $x is spelled apart';

my $sub = <<'SRC';
sub ld { "l" . $_[0] }
sub f { my $y = 1; my $r = ld($y); { my $y = 2; $r .= ld($y) } return $r . ld($y) }
print f(), "\n";
SRC
is scalar_symbols(graph_of($sub), 'main::f'), [ 'y', 'y__2' ],
    'likewise in a named sub';

# The Perl it renders to still gives perl's answer.
for my $s ($src, $sub) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($s));
    is run_perl($out // ''), run_perl($s), 'renders to the same output'
        or diag $out // $d->gap;
}

done_testing;
