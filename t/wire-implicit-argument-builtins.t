# ABOUTME: localtime/gmtime with no argument take an implicit $_ or time().
# ABOUTME: Popping one regardless underflowed the stack -- an internal error, masked.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub sub_graph ($src, $name) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    my ($k) = grep { /::\Q$name\E$/ } keys $data->{methods}->%*;
    return $k ? $data->{methods}{$k} : undef;
}

# `localtime` with no argument defaults to `time`, and the op carries NO
# CHILD to say so -- flags=3 where the explicit form is flags=7 (OPf_KIDS).
# OpMap declares pop_count 1, so the handler popped a node that was not
# there and StackSim died:
#
#     B::SoN: INTERNAL ERROR translating main::c (masked as a silent skip):
#     Stack underflow at StackSim.pm line 25
#
# Masked, so the sub simply vanished from the wire with no method entry at
# all -- the crashes-mask-GAPs shape: an internal error firing before any
# honest refusal could.
subtest 'a no-argument localtime reaches the wire' => sub {
    for my $call ('localtime', 'gmtime') {
        for my $form ("$call", "$call(0)") {
            my $g = sub_graph(qq{sub c { my (\$a, \$b) = $form; return \$b }\nc();\n}, 'c');
            ok defined $g, "$form: the sub reaches the wire at all";
        }
    }
};

# NOT FIXED HERE, and a DIFFERENT defect: the list-assign statement is still
# dropped, because padrange SKIPs a non-@_ LHS and the trailing aassign then
# reads the RHS as its target list. See
# t/wire-padrange-non-args-source.t, which pins that for times/localtime.
# This file is only about the underflow that stopped the sub existing at all.
subtest 'the statement itself is still dropped' => sub {
    my $todo = todo 'padrange SKIPs a non-@_ LHS -- see wire-padrange-non-args-source.t';
    for my $call ('localtime', 'gmtime') {
        my $g = sub_graph(qq{sub c { my (\$a, \$b) = $call; return \$b }\nc();\n}, 'c');
        next unless defined $g;
        my @ops = map { $_->{op} } $g->{nodes}->@*;
        ok scalar(grep { $_ eq 'Call' } @ops), "$call: its Call is in the graph"
            or diag "ops = @ops";
    }
};

done_testing;
