# ABOUTME: An elsif arm whose only store sits in the true arm of a nested if keeps its own
# ABOUTME: If: the arm scan descends into nested branches for stores into memory scalars.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE LAST control-fork IN CHALK'S LIB (wire v2 plan, stage 1:
# Chalk::Bootstrap::Perl::Actions::SubroutineDefinition), reduced:
#
#     if ($x) { Y(1) }
#     elsif ($y) { if ($y > 1) { $has = 1 } else { my $z = 1 } }
#     Y($has);
#
# `$has` lives in memory (it is handed to a sub). The elsif is an `and` whose
# arm is the nested if; "does this arm need control flow" asked
# _arm_has_field_store, which walked the arm by ->next only: the nested if's
# FALSE arm is on that walk, its TRUE arm (->other) is not. With a store in the
# false arm the elsif got its If; with the store only in the true arm it got
# none, the nested If hung off the outer else-Proj beside the join (one Proj,
# two successors), and the store's memory never reached the join's memory Phi.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return JSON::PP->new->utf8->decode($json);
}
sub forks ($w) { [ map {"$_->{graph}#$_->{node} $_->{detail}"} grep { $_->{rule} eq 'control-fork' } SoN::Verify::verify($w)->{violations}->@* ] }

my %src = (
    'a scalar handed to a sub' => <<'EOS',
sub Y { print defined $_[0] ? $_[0] : 'u', "\n" }
sub S {
    my ($x, $y) = @_;
    my $has;
    if ($x) { Y(1) }
    elsif ($y) { if ($y > 1) { $has = 1 } else { my $z = 1 } }
    Y($has);
}
S(0, 2); S(0, 1); S(1, 0); S(0, 0);
EOS
    'a package scalar' => <<'EOS',
our $has;
sub S {
    my ($x, $y) = @_;
    if ($x) { print "x\n" }
    elsif ($y) { if ($y > 1) { $has = $y } else { my $z = 1 } }
    return;
}
S(0, 2); S(0, 1); S(1, 0);
print $has, "\n";
EOS
    'the reduced SubroutineDefinition' => <<'EOS',
sub B { 1 }
sub Y { join ",", scalar $_[0]->@*, $_[1] // 'u' }
sub S {
    my ($has, @body);
    for my $leaf (@_) {
        my $focus = $leaf->[0];
        my $rule = $leaf->[1];
        if ($rule eq 'Block') { B($focus) }
        elsif (ref($focus) eq 'ARRAY') {
            if ($rule eq 'S') { $has = 1 }
            else { if (!@body) { @body = $focus->@* } }
        }
    }
    return Y(\@body, $has);
}
print S([{}, 'Block'], [[1,2], 'S'], [[3], 'q'], [[4,5], 'q']), "\n";
EOS
);

for my $name ( sort keys %src ) {
    my $w = wire( $src{$name} );
    ok scalar( grep { /::S\z/ } keys $w->{methods}->%* ), "$name: S is translated"
        or diag scalar `cat $dir/err`;
    is forks($w), [], "$name: no control node has two successors";
}

# NOT COVERED: the same elsif as the sub's last statement (its value is the
# sub's) is taken by the value short-circuit handler, which does not ask the
# field-store question; asking it there refused chalk graphs that merge a
# value `&&` in a loop body, so that shape still forks (and chalk refuses a
# fork by name). No program of the corpus, the probes or chalk's lib has it.

done_testing;
