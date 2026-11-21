# ABOUTME: A dereference remade as a copy (`my @in = $s->inputs->@*` then read) keeps
# ABOUTME: its memory version as mem_in on wire v2, not as a v1 positional input.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Verify;

# Found at the stage 2+3 integration: chalk's Builder::array_stmt rose by one
# read-unversioned:through-ref on chalk2. The copy was made from the read's
# v1_inputs, so on v2 it carried the memory operand as a second input, and no
# mem_in.
my $dir = tempdir( CLEANUP => 1 );
open my $o, '>', "$dir/c.pl" or die $!;
print $o 'sub c { my ($b, $s) = @_; my @in = $s->inputs->@*; my ($x, @v) = @in; return scalar @v } 1;', "\n";
close $o;

sub wire ($n) {
    my $j = qx($^X -Ilib -MO=-q,SoN,json,wire=$n,not_package=SoN $dir/c.pl 2>/dev/null);
    return decode_json($j);
}
sub copy_of ($w) {
    my @n = $w->{methods}{'main::c'}{nodes}->@*;
    my ($c) = grep { $_->{op} eq 'PostfixDeref' && $_->{fields}{copy} } @n;
    return $c;
}

my $w2 = wire(2);
my $c2 = copy_of($w2);
ok $c2, 'wire 2 has the copy';
is scalar $c2->{inputs}->@*, 1, '... with its reference as its one input';
ok defined $c2->{mem_in}, '... and its memory version as mem_in';
is [ grep { $_->{graph} eq 'main::c' } SoN::Verify::verify($w2)->{violations}->@* ], [], 'no violation in the graph';

my $c1 = copy_of( wire(1) );
is scalar $c1->{inputs}->@*, 2, 'wire 1 keeps the memory operand last, as it was';

done_testing;
