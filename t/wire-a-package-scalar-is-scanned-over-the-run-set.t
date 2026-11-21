# ABOUTME: A package scalar written by any graph on the wire is read through memory:
# ABOUTME: the write scan covers anon subs, ADJUST blocks, phase blocks and unfollowed classes.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE DEFECT. W1's rule -- a written package scalar is never carried round a
# loop on a value Phi -- is decided by _package_scalars_written, and that scan
# read the program's root and the named subs of the program's and its followed
# modules' packages. The wire holds more graphs than that: an anon sub's body,
# a class's ADJUST block, a BEGIN or END block, and the methods of a class
# from a file B::SoN does not follow (a lower-case module) but emits because
# the program calls it. A loop in one of those, storing a scalar nothing the
# scan read stores, still got its header Phi:
#
#     my $f = sub { $main::g += 10 };
#     my $run = sub { $main::g = 0; for my $i (1..3) { $main::g = $main::g + 1; $f->() } };
#     $run->(); print "$main::g\n";
#
# perl 33; chalk 13 once its WireCheck no longer refuses the shape.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return length $json ? JSON::PP->new->utf8->decode($json) : undef;
}

sub carried ($w) {
    [ map { "$_->{graph} $_->{op}#$_->{node} $_->{detail}" }
      grep { $_->{rule} eq 'package-scalar-loop-value' } SoN::Verify::verify($w)->{violations}->@* ];
}

# The library: a class in a lower-case module (perlmodlib's pragma names are
# not followed), so its methods are not "user code" and are on the wire.
mkdir "$dir/w1lib" or die $!;
{
    open my $o, '>', "$dir/w1lib/w1counter.pm" or die $!;
    print $o <<'PM';
use v5.38;
use feature 'class';
no warnings 'experimental::class';
class w1counter {
    field $step :param = 10;
    method bump { $w1counter::n += $step; return }
    method run {
        $w1counter::n = 0;
        for my $i (1..3) { $w1counter::n = $w1counter::n + 1; $self->bump; }
        return $w1counter::n;
    }
}
1;
PM
    close $o;
}

# shape => [ source, the graph that holds the loop ]
my %shape = (
    'a method of a class in a module that is not followed' => [
        qq{use lib '$dir/w1lib'; use w1counter; my \$o = w1counter->new; my \$r = \$o->run; print "\$r\\n";},
        qr/\Aw1counter::run\z/ ],
    'an anon sub, its writer another anon sub' => [
        'my $f = sub { $main::g += 10 }; my $run = sub { $main::g = 0; for my $i (1..3) { $main::g = $main::g + 1; $f->(); } }; $run->(); print "$main::g\n";',
        qr/__ANON__/ ],
    'an ADJUST block, its writer another class\'s ADJUST' => [
        'use v5.38; use feature "class"; no warnings; class C { field $x = 1; ADJUST { $main::g += 10 } } class D { field $y; ADJUST { $main::g = 0; for my $i (1..3) { $main::g = $main::g + 1; C->new; } } } D->new; print "$main::g\n";',
        qr/\AD::__ADJUST_0\z/ ],
);

for my $name ( sort keys %shape ) {
    subtest $name => sub {
        my ( $src, $holder ) = $shape{$name}->@*;
        my $w = wire($src) or return fail 'no wire';
        is carried($w), [], 'no value Phi carries the package scalar';

        my ($graph) = grep { $_ =~ $holder && grep { $_->{op} eq 'Loop' } $w->{methods}{$_}{nodes}->@* } sort keys $w->{methods}->%*;
        ok defined $graph, 'the graph with the loop is on the wire' or return;
        my @nodes = $w->{methods}{$graph}{nodes}->@*;
        my %by    = map { $_->{id} => $_ } @nodes;
        my ($loop) = grep { $_->{op} eq 'Loop' } @nodes;
        my ($mphi) = grep { $_->{op} eq 'Phi' && $_->{fields}{memory} && $_->{fields}{region} == $loop->{id} } @nodes;
        ok $mphi, 'the loop has a memory Phi' or return;
        # The loop's store is computed from a read at a version made in the
        # loop (the memory Phi, or what follows it), not from a value Phi.
        my @in_loop = grep { $_->{op} eq q(EntryDef) && defined $_->{mem_in}
                             && $by{ $_->{mem_in} }{op} ne q(MemStart) } @nodes;
        my @stores = grep { $_->{op} eq 'EntryWrite' && defined $_->{control_in} } @nodes;
        ok scalar( grep { my $s = $_; grep { _reaches( \%by, $s->{inputs}[1], $_->{id} ) } @in_loop } @stores ),
            'a store in the loop is computed from a read through memory';
    };
}

# THE SAME WITH NO STORE IN THE LOOP'S OWN GRAPH, and no Phi to find: a read
# before the loop bound the scalar, the loop's read forwarded that binding, and
# the writer -- the callee -- was in a graph the scan had not read. chalk as it
# stood printed four empty lines for perl's "", 10, 20, 30.
#     my $f = sub { $main::g += 10 }; my $x = $main::g;
#     for my $i (1..3) { print "$main::g\n"; $f->() }
{
    open my $o, '>', "$dir/w1lib/w1step.pm" or die $!;
    print $o <<'PM';
use v5.38;
use feature 'class';
no warnings 'experimental::class';
class w1step {
    field $step :param = 10;
    method bump { $w1step::n += $step; return }
}
1;
PM
    close $o;
}
my %reader = (
    'the writer a method of a class in a module that is not followed' => [
        qq{use lib '$dir/w1lib'; use w1step; my \$o = w1step->new; my \$x = \$w1step::n; for my \$i (1..3) { print "\$w1step::n\\n"; \$o->bump; } print "\$w1step::n\\n";},
        'n' ],
    'the writer an anon sub' => [
        'my $f = sub { $main::g += 10 }; my $x = $main::g; for my $i (1..3) { print "$main::g\n"; $f->(); } print "$main::g\n";',
        'g' ],
    'the writer an ADJUST block' => [
        'use v5.38; use feature "class"; no warnings; class C { field $x = 1; ADJUST { $main::g += 10 } } my $x = $main::g; for my $i (1..3) { print "$main::g\n"; C->new; } print "$main::g\n";',
        'g' ],
    'the writer a sort block of a sub the loop calls' => [
        'sub srt { my @a = sort { $main::g += 10; $a <=> $b } (2, 1); return } my $x = $main::g; for my $i (1..3) { print "$main::g\n"; srt(); } print "$main::g\n";',
        'g' ],
);
for my $name ( sort keys %reader ) {
    subtest "a loop that only reads it: $name" => sub {
        my ( $src, $sym ) = $reader{$name}->@*;
        my $w = wire($src) or return fail 'no wire';
        my @nodes = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        my %by    = map { $_->{id} => $_ } @nodes;
        my ($loop) = grep { $_->{op} eq 'Loop' } @nodes or return fail 'no Loop';
        my ($mphi) = grep { $_->{op} eq 'Phi' && $_->{fields}{memory} && $_->{fields}{region} == $loop->{id} } @nodes;
        ok $mphi, 'the loop has a memory Phi' or return;
        my @reads = grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq $sym && defined $_->{mem_in} } @nodes;
        ok scalar( grep { $_->{mem_in} == $mphi->{id} } @reads ), 'the read in the loop is at the loop\'s memory Phi';
        my @prints = grep { $_->{op} eq 'Print' } @nodes;
        my ($pre) = grep { $by{ $_->{mem_in} }{op} eq q(MemStart) } @reads;
        ok !( $pre && grep { _reaches( \%by, $_->{id}, $pre->{id} ) } @prints ),
            'nothing printed is computed from the read before the loop';
    };
}

sub _reaches ( $by, $from, $to, $seen = {} ) {
    return 0 if !defined $from || ref $from || $seen->{$from}++;
    return 1 if $from == $to;
    return scalar grep { _reaches( $by, $_, $to, $seen ) } ( $by->{$from}{inputs} // [] )->@*;
}

done_testing;
