# ABOUTME: A void list assignment whose scalars live in the stash is its EntryWrites: no Assign
# ABOUTME: is left beside them for the v2 writer to call a record of package variables (V7).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# WHY. `($a1, $b1) = ($b1 + 1, $a1 + 2)` stores each package scalar by an
# EntryWrite, position by position; the list Assign the handler made first
# stayed on the wire, on neither chain, read by nothing -- a `record` whose
# targets are not `my` variables (V7: probes lo12, m3; chalk's lib 4).
# AS ITS SUB'S LAST STATEMENT (probes pl13, aun17f) the assignment is the
# sub's value, in the caller's context: perl gives a list caller the targets
# as they are after it, a scalar caller the right side's count. That is the
# two readings a Return carries for `return @a` (inputs [list, scalar]), so
# the Assign goes there too: the targets read at the last store's version,
# and the count.
my $dir = tempdir( CLEANUP => 1 );
my $n = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json,wire=2,not_package=SoN $f 2>/dev/null) );
}
sub v7 ($w) { [ map { "$_->{graph}#$_->{node}" } grep { $_->{rule} eq 'record' } SoN::Verify::verify($w)->{violations}->@* ] }

for my $case (
    [ q{our ($a1, $b1) = (0, 0); sub sw { ($a1, $b1) = ($b1 + 1, $a1 + 2); 1 } for (1..3) { $a1 = $a1 + 1; sw() } print "$a1 $b1\n";}, 'a swap of package scalars in a sub' ],
    [ q{our ($a1, $b1) = (1, 2); { local ($a1, $b1) = ($b1, $a1); print "$a1$b1" } print "$a1$b1\n";}, 'a local list assignment (lo12)' ],
    [ q{our $p = 1; ($p, my $q) = (3, 4); print "$p $q\n";}, 'a package scalar beside a `my` (m3)' ],
) {
    my ( $src, $name ) = @$case;
    is v7( wire($src) ), [], "$name: no record of a package variable";
}

# The value of a list assignment to package scalars that ends its sub.
for my $case (
    [ q{our ($a1, $b1) = (0, 0); sub sw { ($a1, $b1) = ($b1 + 1, $a1 + 2) } for (1..3) { $a1 = $a1 + 1; sw() } print "$a1 $b1\n";}, 'pl13', 2 ],
    [ q{our ($a1, $b1) = (1, 2); sub sw { ($a1, $b1) = ($b1, $a1) } my $s = "$a1$b1"; sw(); print "$s $a1$b1\n";}, 'aun17f', 2 ],
    [ q{our ($a1, $b1); sub sw { ($a1, $b1) = (7, 8, 9) } my @r = sw(); my $n = sw(); print "@r $n\n";}, 'more values than targets', 3 ],
) {
    my ( $src, $name, $count ) = @$case;
    my $w = wire($src);
    is v7($w), [], "$name: no record of a package variable";
    my %n   = map { ( $_->{id} => $_ ) } $w->{methods}{'main::sw'}{nodes}->@*;
    my ($r) = grep { $_->{op} eq 'Return' } values %n;
    is scalar $r->{inputs}->@*, 2, "$name: the Return carries two readings";
    my ( $list, $scalar ) = map { $n{$_} } $r->{inputs}->@*;
    is [ $list->{op}, $list->{stamp} ], [ 'ArrayLiteral', 'List' ], "$name: the list reading is a list";
    is [ map { "$n{$_}{op} $n{$_}{fields}{symbol}" } $list->{inputs}->@* ], [ 'EntryDef a1', 'EntryDef b1' ], "$name: of the targets";
    is [ map { $n{$_}{mem_in} } $list->{inputs}->@* ], [ ( $r->{mem_in} ) x 2 ], "$name: read after the stores";
    is [ $scalar->{op}, $scalar->{fields}{value} ], [ 'Constant', $count ], "$name: the scalar reading is the right side's count";
}

# THE RIGHT SIDE'S COUNT IS OF WHAT IT FLATTENS: `($a1, $b1) = @x` is 3 for
# three elements (the record names the elements it copied, so counting the
# Assign's inputs said 2; @x unstamped when it is read counted as one).
{
    my $w = wire(q{our ($a1, $b1); my @x = (1, 2, 3); sub sw { ($a1, $b1) = @x } my $n = sw(); print "$n\n";});
    my %n   = map { ( $_->{id} => $_ ) } $w->{methods}{'main::sw'}{nodes}->@*;
    my ($r) = grep { $_->{op} eq 'Return' } values %n;
    my $c   = $n{ $r->{inputs}[1] // -1 } // {};
    is [ $c->{op}, map { "$n{$_}{op} $n{$_}{fields}{symbol}" } ( $c->{inputs} // [] )->@* ], [ 'Count', 'PadAccess x' ],
        'an array on the right: the scalar reading counts it';
}
# ONLY THE ASSIGNMENT THAT IS THE VALUE IN THE CALLER'S CONTEXT: one made in
# scalar context and returned through a `my` is already its count's, or the
# Assign (chalk refuses it by name) -- never given a list reading.
{
    my $w = wire(q{our ($p, $q); my @x = (1, 2, 3); sub f { my $n = (($p, $q) = @x); $n } print f(), "\n";});
    my ($r) = grep { $_->{op} eq 'Return' } $w->{methods}{'main::f'}{nodes}->@*;
    is scalar $r->{inputs}->@*, 1, 'a list assignment in scalar context, returned: one reading';
}
done_testing;
