# ABOUTME: A package scalar in a foreach, map or grep list names the memory version the list
# ABOUTME: is made at, and the verifier no longer excuses one that does not (final audit 4.7).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;
use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub src ($s) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $s;
    close $o;
    return $f;
}
sub wire ($f) { JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err) ) }
sub nd ( $id, $op, $in, %rest ) {
    my %n = ( id => $id, op => $op, inputs => $in );
    $n{control_in} = delete $rest{ctl} if exists $rest{ctl};
    $n{mem_in}     = delete $rest{mem} if exists $rest{mem};
    $n{mem_out}    = JSON::PP::true if delete $rest{out};
    $n{fields}     = {%rest} if %rest;
    return \%n;
}

# The verifier took an item of an alias list -- the list a foreach walks, used
# only as a container -- for a place, so an EntryDef there with no mem_in passed
# (class E). It is a read of the variable where the list is made.
subtest 'the verifier: an unversioned package scalar in a foreach list' => sub {
    my @nodes = (
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'EntryDef', [], package => 'main', sigil => '$', symbol => 'x' ),
        nd( 4, 'EntryWrite', [ 3, 2 ], ctl => 0, mem => 1, out => 1 ),
        nd( 5, 'ArrayLiteral', [3] ),
        nd( 6, 'Subscript', [ 5, 2 ], ctl => 4, mem => 4, kind => 'array' ),
        nd( 7, 'Print', [6], ctl => 6 ),
        nd( 8, 'Return', [2], ctl => 7, mem => 4 ),
    );
    my $w = { version => 2, methods => { g => { returns => [8], nodes => \@nodes } } };
    is [ map { "$_->{rule}" } SoN::Verify::verify($w)->{violations}->@* ], ['read-unversioned:package'],
        'is read-unversioned';
    $nodes[3] = nd( 3, 'EntryDef', [], package => 'main', sigil => '$', symbol => 'x' );
    splice @nodes, 5, 1, nd( 5, 'ArrayLiteral', [9] );
    push @nodes, nd( 9, 'EntryDef', [], mem => 4, package => 'main', sigil => '$', symbol => 'x' );
    is [ map { "$_->{rule}" } SoN::Verify::verify($w)->{violations}->@* ], [], 'named at its version, it is not';
};

# perl aliases the variable itself: the write through $_ is $x's.
for my $case (
    [ 'our $x = 1; for ($x) { $_ = 5 } print "$x\n";', "5\n" ],
    [ 'our $x = 5; for my $y ($x) { $y = 6 } print "$x\n";', "6\n" ],
) {
    my ( $s, $want ) = @$case;
    my $f = src($s);
    is scalar qx($^X $f), $want, "perl: $s";
    my $w = wire($f);
    my @items = grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq 'x' }
        map { my $l = $_; map { my $i = $_; grep { $_->{id} == $i } $w->{methods}{'main::__PROGRAM__'}{nodes}->@* } $l->{inputs}->@* }
        grep { $_->{op} eq 'ArrayLiteral' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    is scalar @items, 1, '... the list holds $x';
    ok defined $items[0]{mem_in}, '... at a version';
    is [ map { "$_->{rule}" } SoN::Verify::verify($w)->{violations}->@* ], [], '... and the wire verifies';
    # (the deparser refuses it by name, as it did before: never a wrong answer)
    my $d   = SoN::Deparse->new;
    my $out = $d->render($w);
    if ( defined $out ) { is scalar qx($^X @{[ src($out) ]} 2>&1), $want, "... the deparser gives perl's answer" }
    else                { like $d->gap, qr/\AGAP: /, '... the deparser refuses it by name' }
}

done_testing;
