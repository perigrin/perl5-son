# ABOUTME: A `my` scalar declared earlier and filled by a placed list assign is read at that
# ABOUTME: assign's memory version: reads after two such assigns are two nodes, not the slot.

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
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# Stage 6 found it (docs/memory/wire-v1-is-gone.md): the read of $x was the
# target PadAccess itself -- one node, no version -- so a value made from it
# after the first assign was made once and read again after the second.
for my $case (
    [ 'two list assigns with an array beside the scalar',
        q{my ($x, @r); ($x, @r) = (1, 2); print "$x|"; ($x, @r) = (4, 5); print "$x\n";}, 2 ],
    [ 'fk7: bound in two ifs, read after each',
        q{my ($x, @r); my @a = (1); if (!@a) { ($x, @r) = (1, 2, 3) } print scalar(@r), "\n"; if (@a) { ($x, @r) = (4, 5, 6) } print "$x @r\n";}, undef ],
    [ 'from a call, twice',
        q{sub g { return @_ } my ($x, $y); ($x, $y) = g(1, 2); my $s = "$x$y"; ($x, $y) = g(3, 4); print "$s $x$y\n";}, 2 ],
) {
    my ( $what, $src, $reads ) = $case->@*;
    subtest $what => sub {
        my $data  = graph_of($src) or return fail 'a wire';
        my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        my %by    = map { $_->{id} => $_ } @nodes;
        # The target slot is used only as a target: never read by name.
        my %target = map { my $a = $_; map { $_ => 1 } $a->{inputs}->@[ 0 .. $a->{fields}{targets} - 1 ] }
            grep { $_->{op} eq 'Assign' && $_->{fields}{targets} && !$_->{fields}{record} } @nodes;
        my @by_name = grep {
            my $u = $_;
            !( $u->{op} eq 'Assign' && $u->{fields}{targets} )
                && grep { $target{$_} && $by{$_}{op} eq 'PadAccess' && $by{$_}{fields}{sigil} eq '$' } $u->{inputs}->@*
        } @nodes;
        is [ map { "$_->{op}#$_->{id}" } @by_name ], [], 'no target slot is read by name';
        if ( defined $reads ) {
            my @x = grep { $_->{op} eq 'PadAccess' && $_->{fields}{symbol} eq 'x' && defined $_->{mem_in} } @nodes;
            is scalar(@x), $reads, "$reads reads of \$x, each at a version";
        }
        my $d   = SoN::Deparse->new;
        my $out = $d->render($data);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

done_testing;
