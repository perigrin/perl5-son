# ABOUTME: A package scalar a loop body assigns is read through the loop's memory Phi,
# ABOUTME: not carried round the loop as a value Phi no callee's write can reach.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE DEFECT (audit 2026-11-19, finding 1, class W1). A written package scalar
# is never value-forwarded -- some other sub can always assign it -- except
# that a loop which assigned it carried it on a header Phi (@LOOP_PHI_KEYS).
# The exception was made when a memory read in a loop named the PRE-LOOP
# version; loops have had a memory Phi since, and the exception outlived its
# reason. With it,
#
#     our $g = 0; sub bump { $g += 10 }
#     for my $i (1..3) { $g = $g + 1; bump(); }  print "$g\n";
#
# read `$g` from the Phi on every pass, where bump's `+= 10` never arrives:
# perl 33, the wire 13. Eleven probes; one never ended.

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
    [ map { "$_->{op}#$_->{node} $_->{detail}" }
      grep { $_->{rule} eq 'package-scalar-loop-value' } SoN::Verify::verify($w)->{violations}->@* ];
}

my %shape = (
    'a foreach that assigns it and calls its writer' =>
        'our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); } print "$g\n";',
    'a while loop' =>
        'our $g = 0; sub bump { $g += 10 } my $i = 0; while ($i < 3) { $i++; $g = $g + 1; bump(); } print "$g\n";',
    'an increment' =>
        'our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g++; bump(); } print "$g\n";',
    'a string append' =>
        'our $s = ""; sub ap { $s .= $_[0] } for my $c (1..3) { $s .= "-"; ap($c) } print "$s\n";',
    'a list foreach' =>
        'our $g = 0; sub bump { $g += 10 } my @l = (1,2,3); for my $i (@l) { $g = $g + 1; bump(); } print "$g\n";',
    'with no callee at all' =>
        'our $n = 0; my $i = 0; while ($i < 3) { $n++; $i++ } print "n=$n\n";',
    'a loop condition that calls its writer' =>
        'our $n = 0; sub step { $n++ < 3 } my $t = 0; while (step()) { $t += $n; $n = $n + 0 } print "$t $n\n";',
);

for my $name ( sort keys %shape ) {
    subtest $name => sub {
        my $w = wire( $shape{$name} ) or return fail 'no wire';
        is carried($w), [], 'no value Phi carries the package scalar';

        my @nodes = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        my %by    = map { $_->{id} => $_ } @nodes;
        my ($loop) = grep { $_->{op} eq 'Loop' } @nodes or return fail 'no Loop';
        my ($mphi) = grep { $_->{op} eq 'Phi' && $_->{fields}{memory} && $_->{fields}{region} == $loop->{id} } @nodes;
        ok $mphi, 'the loop has a memory Phi' or return;

        # Every write of the scalar in this graph stores a value that is not a
        # read of the pre-loop version: nothing computed from before the loop
        # is stored on every pass.
        my @reads = grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{sigil} // '' ) eq '$'
                           && $_->{fields}{symbol} =~ /\A[gsn]\z/ && defined $_->{mem_in} } @nodes;
        ok scalar(@reads), 'the scalar is read through memory';
        my @pre = grep { $by{ $_->{mem_in} }{op} eq q(MemStart) } @reads;
        my @stored_from_pre = grep {
            my $r = $_;
            grep { $_->{op} eq 'EntryWrite' && defined $_->{control_in} && _reaches( \%by, $_->{inputs}[1], $r->{id} ) } @nodes
        } @pre;
        is scalar(@stored_from_pre), 0, 'no store in the loop is computed from the version before it';
    };
}

# THE SAME OUTSIDE A LOOP, for every `op=`. The old value of a read-modify-
# write was the scope binding (`.=`) or the unversioned name (`+=`): after a
# call that wrote the scalar, `$s .= "-"` appended to what $s held before it.
#     our $s = ""; sub ap { $s .= $_[0] } $s .= "-"; ap("a"); $s .= "-"; ap("b");
#     perl -a-b     the wire --b
my %rmw = (
    q{.=}  => q{our $s = ""; sub ap { $s .= $_[0] } $s .= "-"; ap("a"); $s .= "-"; ap("b"); print "$s\n";},
    q{.= of an interpolation} => q{our $s = "q"; sub ap { $s .= $_[0] } ap("a"); $s .= "-$s"; ap("b"); print "$s\n";},
    q{+=}  => q{our $s = 1; sub ap { $s += $_[0] } $s += 1; ap(1); $s += 5; ap(1); print "$s\n";},
    q{*=}  => q{our $s = 1; sub ap { $s += $_[0] } $s *= 2; ap(1); $s *= 5; ap(1); print "$s\n";},
    q{++}  => q{our $s = 1; sub ap { $s += $_[0] } $s++; ap(1); $s++; ap(1); print "$s\n";},
);
for my $name ( sort keys %rmw ) {
    subtest "a read-modify-write after a call reads what the call left: $name" => sub {
        my $w = wire( $rmw{$name} ) or return fail 'no wire';
        my @nodes = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        my %by    = map { $_->{id} => $_ } @nodes;
        my ($call) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'main::ap' } @nodes;
        my ($write) = grep { $_->{op} eq 'EntryWrite' && ( $_->{control_in} // -1 ) == $call->{id} } @nodes;
        ok $write, 'a store follows the first call' or return;
        my @reads = grep { $_->{op} eq q(EntryDef) && ( $_->{mem_in} // -1 ) == $call->{id} } @nodes;
        ok scalar( grep { _reaches( \%by, $write->{inputs}[1], $_->{id} ) } @reads ),
            'its value is computed from a read at the call';
    };
}

sub _reaches ( $by, $from, $to, $seen = {} ) {
    return 0 if !defined $from || ref $from || $seen->{$from}++;
    return 1 if $from == $to;
    return scalar grep { _reaches( $by, $_, $to, $seen ) } ( $by->{$from}{inputs} // [] )->@*;
}

done_testing;
