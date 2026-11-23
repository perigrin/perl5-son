# ABOUTME: A list read of an array early in a loop body sees a write to it later in the body on the next
# ABOUTME: pass, whatever the write is: a foreach alias, a callee's `$_`, a slice, a map's `$_`, an inner loop.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );

sub graph_of ($src) {
    my $file = "$dir/p.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out  = qx($^X -Ilib -MO=-q,SoN,json $file 2>/dev/null);
    my $data = eval { JSON::PP->new->utf8->decode($out) } or return;
    my %by   = map { ( $_->{id} => $_ ) } $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    return \%by;
}

# The joins whose list is the literal as first built: every element a Constant.
sub joins_of_the_literal ($by) {
    return grep {
        my @ops = map { $by->{$_}{op} // '' } grep { !ref } $_->{inputs}->@*;
        $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'join'
            && @ops > 1 && !grep { $_ ne 'Constant' } @ops[ 1 .. $#ops ];
    } values %$by;
}

# WHY: the read is walked before the write, so the walk has not marked the
# literal when it flattens it, and on the next pass perl reads what the write
# left: `1,2 1,2` for perl's `1,2 1x,2x` (a silent wrong answer since stage
# 9a). The sealing sees the mark the walk made later, the loop learns the
# slot, and its header marks it on the walk again.
my %body = (
    'a foreach alias'          => 'for (@a) { $_ .= "x" }',
    'a named foreach alias'    => 'for my $e (@a) { $e .= "x" }',
    'a callee writing $_'      => 'for (@a) { bump() }',
    'a slice store'            => '@a[0,1] = ("p$i", "q$i")',
    'a map writing $_'         => 'map { $_ .= "x" } @a',
    'a grep writing $_'        => 'my @g = grep { $_ .= "y"; 1 } @a',
    'a foreach in an inner loop' => 'for my $j (1..1) { for (@a) { $_ .= "x" } }',
);
for my $kind ( sort keys %body ) {
    subtest "$kind later in the body" => sub {
        my $by = graph_of(<<"EOS") or return fail 'no graph';
sub bump { \$_ .= "x" }
my \@a = (1, 2); my \@r;
for my \$i (1 .. 2) { push \@r, join(",", \@a); $body{$kind} }
print "\@r\\n";
EOS
        is [ joins_of_the_literal($by) ], [], 'the read is not the literal as first built';
    };
}

# THE READ IN AN INNER LOOP, the write after it in the outer body: the inner
# loop's sealing comes before the write, the outer one's learns it.
subtest 'a read in an inner loop, the write after it' => sub {
    my $by = graph_of(<<'EOS') or return fail 'no graph';
my @a = (1, 2); my @r;
for my $i (1 .. 2) { for my $j (1 .. 2) { push @r, join(",", @a) } for (@a) { $_ .= "x" } }
print "@r\n";
EOS
    is [ joins_of_the_literal($by) ], [], 'the read is not the literal as first built';
};

# A RETURN READS THE LITERAL TOO, outside the flatten: `return @a` on the
# second pass returned the array as first built (`1,2` for perl's `1x,2x`).
subtest 'a return of the array before the write' => sub {
    my $file = "$dir/r.pl";
    open my $fh, '>', $file or die $!;
    print $fh <<'EOS';
sub f { my @a = (1,2); for my $i (1..3) { return @a if $i == 2; for (@a) { $_ .= "x" } } return }
print join(",", f()), "\n";
EOS
    close $fh;
    my $data = JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $file 2>/dev/null) );
    ok $data->{methods}{'main::f'}, 'f has a graph' or return;
    my %by   = map { ( $_->{id} => $_ ) } $data->{methods}{'main::f'}{nodes}->@*;
    # (the value the sub returns by that edge is a List of the elements)
    my @of_literal = grep {
        my @in = grep { !ref } $_->{inputs}->@*;
        $_->{op} eq 'ArrayLiteral' && ( $_->{stamp} // '' ) eq 'List' && @in == 2
            && !grep { ( $by{$_}{op} // '' ) ne 'Constant' } @in;
    } values %by;
    is [ map { $_->{id} } @of_literal ], [], 'no return gives the literal as first built';
};

# NOT A FRESH ARRAY: a `my @a` the pass declares is built again each pass, so
# its literal is the array at the read -- flattened, as before.
subtest 'an array the pass declares is still flattened' => sub {
    my $by = graph_of(<<'EOS') or return fail 'no graph';
my @r;
for my $i (1 .. 2) { my @a = (1, 2); push @r, join(",", @a); for (@a) { $_ .= "x" } }
print "@r\n";
EOS
    is scalar( joins_of_the_literal($by) ), 1, 'the join is over the literal';
};

done_testing;
