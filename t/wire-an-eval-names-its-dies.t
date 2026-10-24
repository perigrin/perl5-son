# ABOUTME: Each die names the block eval that lexically holds it (eval_id, on both), and a
# ABOUTME: read of $@ after an eval, on the main walk, is its own node pinned where it is.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return JSON::PP->new->decode($j)->{methods}{'main::__PROGRAM__'}{nodes};
}

# WHICH EVAL CATCHES A DIE is lexical within a graph. A consumer that lowers
# only some evals as branches must know a die belongs to one it did not --
# chalk sent a die in an inner eval to the outer one's end.
my $n = nodes_of(q{my $c = $ENV{NO_SUCH_VAR} // 1;
my $o = eval { if ($c) { my $i = eval { die "in\n"; 1 }; print defined $i ? 1 : 0 } die "out\n" if $c; 3 };
die "top\n" unless defined $o;});
my %by = map { $_->{id} => $_ } @$n;
my @regions = sort { $a->{id} <=> $b->{id} } grep { $_->{op} eq 'Region' && defined $_->{fields}{eval_entry} } @$n;
is scalar(@regions), 2, 'two evals';
my %msg_of = map { ($by{ $_->{inputs}[0] }{fields}{value} // '?') => $_->{fields}{eval_id} }
    grep { $_->{op} eq 'Unwind' } @$n;
my ($inner, $outer) = map { $_->{fields}{eval_id} } @regions;
ok defined $inner && defined $outer && $inner ne $outer, 'each eval has its own id';
is $msg_of{"in\n"},  $inner, 'the inner die names the inner eval';
is $msg_of{"out\n"}, $outer, 'the outer die names the outer eval';
is $msg_of{"top\n"}, undef,  'a die in no eval names none';

# $@ AFTER AN EVAL is what the eval left: on the main walk its read is a
# node of its own, pinned where it is, never the read inside the body at the
# same memory version (a guard: chalk relies on it to order the two).
$n = nodes_of(q{my $i = eval { my $j = eval { die "x\n"; 1 }; print "in[$@]"; 2 }; print "out[$@]";});
my @at_reads = grep { $_->{op} eq 'EntryDef' && ($_->{fields}{symbol} // '') eq '@'
    && @{ $_->{inputs} // [] } } @$n;
my @pinned = grep { defined $_->{control_in} } @at_reads;
is scalar(@pinned), 1, 'the read after the evals is pinned';
ok !(grep { $_->{id} == $pinned[0]{id} } grep { !defined $_->{control_in} } @at_reads),
    'and is not the read inside the body';

done_testing;
