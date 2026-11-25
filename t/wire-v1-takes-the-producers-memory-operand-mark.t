# ABOUTME: as_v1 decides which mem_in was an operand by the producer's mark on the wire (`mem_operand`),
# ABOUTME: not by node kind: a placed four-argument substr follows memory and reads none as an operand.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Wire;

# AUDIT 2, clause 3: as_v1 guessed by kind ("wrong for about 30 builtin calls
# in 9000": a four-argument substr, `$#a = N`, ...). The producer knows: a
# node built with its memory as an operand (mem_operand) says so on the wire.

my $dir = tempdir( CLEANUP => 1 );
my $n = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null) );
}
sub nodes ($w) { $w->{methods}{'main::__PROGRAM__'}{nodes} }

{   my $w = wire('my $s = "abc"; my $r = \$s; substr($s, 0, 1) = "z"; print "$s\n";');
    my ($sub) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'substr' && defined $_->{control_in} } nodes($w)->@*;
    ok $sub && defined $sub->{mem_in} && !$sub->{mem_operand}, 'the placed substr follows memory: no mark';
    my ($read) = grep { $_->{op} eq 'PadAccess' && defined $_->{mem_in} } nodes($w)->@*;
    ok $read->{mem_operand}, 'a read built at its version is marked';
    my $v1 = SoN::Wire::as_v1($w);
    my ($sub1) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'substr' && defined $_->{control_in} } nodes($v1)->@*;
    ok !( $sub1->{fields} // {} )->{memory_input}, 'as_v1: the substr gains no memory input';
    ok !grep( { exists $_->{mem_operand} } nodes($v1)->@* ), 'as_v1: the mark is v2\'s, not v1\'s';
}
done_testing;
