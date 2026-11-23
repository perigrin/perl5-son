# ABOUTME: Braun's loop header knows what its OWN body may do: not an enclosing loop's writes, not a grep's
# ABOUTME: list as a rebinding, and an array a call is passed later in the body is read from memory before it.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );

sub graph_of ( $src, $sub ) {
    my $file = "$dir/p.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out  = qx($^X -Ilib -MO=-q,SoN,json $file 2>/dev/null);
    my $data = eval { JSON::PP->new->utf8->decode($out) } or return;
    my %by   = map { ( $_->{id} => $_ ) } $data->{methods}{$sub}{nodes}->@*;
    return \%by;
}

sub derefs_of_a_literal ($by) {
    return grep {
        $_->{op} eq 'PostfixDeref' && ( $_->{fields}{sigil} // '' ) eq '@'
            && ( $by->{ $_->{inputs}[0] }{op} // '' ) eq 'ArrayLiteral'
    } values %$by;
}

# WHY (found by re-running stage 9b's proof with %MUTATED_LITERALS keyed by the
# node: the rows that stayed were the scan's, not the scouts'). The header has
# a Phi for each slot the body may rebind (_may_write_targs), and the walk
# reads a binding's class through it -- a literal's mutation guard, a known
# constructor's class -- until the sealing forwards it.

# THE INNER LOOP'S CYCLE WENT ROUND THE OUTER ONE: its natural exit continues
# the outer body, which re-enters the inner loop, so every slot the outer body
# writes had an inner Phi. `$factory` was a Phi at the call, and the method
# Call lost its class_name (chalk's Analysis::_insert_str_coercions).
subtest 'an inner loop has no Phi for what only the outer body writes' => sub {
    my $by = graph_of( <<'EOS', 'main::f' ) or return fail 'no graph';
package F; sub new { bless {}, shift } sub make { my ($s, $x) = @_; return $x * 2 }
package main;
sub f { my ($gs) = @_; my $n = 0; for my $g (@$gs) { my $factory = F->new(); for my $x (@$g) { $n += $factory->make($x) } } return $n }
print f([[1, 2], [3]]), "\n";
EOS
    my ($make) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'make' } values %$by;
    is $make->{fields}{class_name}, 'F', 'the call knows its invocant is an F';
};

# A GREP'S LIST IS ALIASED, NOT REBOUND, as a foreach's is: a Phi for @p made
# the read in the body a Phi, and the in-loop guard (a slot mutated anywhere in
# the sub is read from memory in a loop) saw no literal to mark -- the stage 9a
# wire pinned it (chalk's Builder::_common_memo, Analysis::_answer_sub_defined).
subtest 'a grep over an array in a loop is no write of the array' => sub {
    my $by = graph_of( <<'EOS', 'main::f' ) or return fail 'no graph';
sub f { my @p = (1, 2); my $n = 0; for my $i (1 .. 2) { $n += grep { $_ > $i } @p } push @p, 3; return $n + @p }
print f(), "\n";
EOS
    ok( scalar( derefs_of_a_literal($by) ), 'the grep reads @p through memory, as a mutated slot in a loop is read' );
};

# A SILENT WRONG ANSWER since stage 9b. A call later in the body may write the
# array's elements (`$_[0] .= "x"`), and on the next pass the read before it
# must see that. The stage 9a scouts walked the body first, and their mark of
# the slot (an array passed to a call) reached the real walk; walked once, the
# read came first and flattened the literal: `1,2 1,2` for perl's `1,2 1x,2`.
subtest 'an array passed to a call later in the body is read from memory' => sub {
    my $by = graph_of( <<'EOS', 'main::__PROGRAM__' ) or return fail 'no graph';
sub bump { $_[0] .= "x" }
my @a = (1, 2); my @r;
for my $i (1 .. 2) { push @r, join(",", @a); bump(@a); }
print "@r\n";
EOS
    my ($join) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'join' } values %$by;
    ok $join, 'there is a join' or return;
    my @ops = map { $by->{$_}{op} } grep { !ref } $join->{inputs}->@*;
    isnt [ @ops[ 1 .. $#ops ] ], [ 'Constant', 'Constant' ], 'the join is not over the literal as first built';
    ok( scalar( derefs_of_a_literal($by) ), '@a is read through memory' );
};

done_testing;
