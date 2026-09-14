# ABOUTME: A handle read is an effect in any context, so it is pinned on control.
# ABOUTME: Two readline calls on one handle return different lines; order is the value.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    my $d = eval { JSON::PP->new->decode($j) } or return undef;
    return $d->{methods}{'main::__PROGRAM__'};
}

# READING A HANDLE ADVANCES IT, so `readline` is an effect even when its value
# is bound. The pinning gate was `$void && $effectful`, and a bound read is not
# void -- measured on `open(TRY,"<$f"); my @got = <TRY>; close(TRY)`:
#
#      4 Call  readline  ci=None      <- NOT on the control chain
#     21 Call  open      ci=0
#     23 Call  close     ci=22
#
# so the read could float anywhere, and the deparse oracle duly emitted it
# BEFORE the open -- reading a handle that was not yet open, then printing
# zero lines. The graph permitted that; nothing in it said otherwise.
#
# Same shape as `require`, whose comment two lines below the gate already says
# "a global-state op is an effect in ANY context, and keying on OPf_WANT_VOID
# silently dropped it".
subtest 'a bound readline is on the control chain' => sub {
    my $g = graph_of(<<'SRC');
my $f = "rl.$$.tmp";
open(TRY, ">$f"); print TRY "x\n"; close(TRY);
open(TRY, "<$f"); my @got = <TRY>; close(TRY);
unlink $f;
print "n=", scalar(@got), "\n";
SRC
    ok $g, 'it translates' or return;

    my ($rl) = grep { ($_->{op} // '') eq 'Call'
                   && (($_->{fields} // {})->{name} // '') eq 'readline' }
               $g->{nodes}->@*;
    ok $rl, 'there is a readline Call' or return;
    ok defined $rl->{control_in},
        'and it names a control predecessor';

    # ORDERED AFTER THE OPEN. A control edge that pointed anywhere would
    # satisfy the check above; what matters is that the open precedes it.
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($seen_open, $cur) = (0, $by{ $rl->{control_in} });
    for (1 .. 40) {
        last unless $cur;
        $seen_open = 1, last
            if ($cur->{op} // '') eq 'Call'
            && (($cur->{fields} // {})->{name} // '') eq 'open';
        $cur = defined $cur->{control_in} ? $by{ $cur->{control_in} } : undef;
    }
    ok $seen_open, '... reached by walking back from the read to an open';
};

# EOF IS THE SAME KIND OF READ -- it consults the handle's state, and a
# pinning rule that named only `readline` would leave it floating.
subtest 'eof is pinned too' => sub {
    my $g = graph_of(<<'SRC');
my $f = "eo.$$.tmp";
open(TRY, ">$f"); print TRY "x\n"; close(TRY);
open(TRY, "<$f"); my $e = eof(TRY); close(TRY);
unlink $f;
print "e=$e\n";
SRC
    ok $g, 'it translates' or return;
    my ($eo) = grep { ($_->{op} // '') eq 'Call'
                   && (($_->{fields} // {})->{name} // '') eq 'eof' }
               $g->{nodes}->@*;
    ok $eo, 'there is an eof Call' or return;
    ok defined $eo->{control_in}, 'and it is on the control chain';
};

# A PURE BUILTIN MUST NOT BE PINNED. Over-pinning would order reads that are
# genuinely free to float, which is the over-broad-guard mistake this file
# has made before.
subtest 'a pure builtin still floats' => sub {
    my $g = graph_of('my $s = "abc"; my $n = length($s); print "$n\n";');
    ok $g, 'it translates' or return;
    my ($len) = grep { ($_->{op} // '') eq 'Length'
                    || (($_->{op} // '') eq 'Call'
                        && (($_->{fields} // {})->{name} // '') eq 'length') }
                $g->{nodes}->@*;
    ok $len, 'there is a length node' or return;
    ok !defined $len->{control_in}, 'and it is NOT pinned on control';
};

done_testing;
