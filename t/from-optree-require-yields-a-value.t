# ABOUTME: A non-void require/dofile is pinned on control AND yields its value.
# ABOUTME: One flag meant both "pin this" and "discard the result", so `require X or die` underflowed.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub translate ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) };
    return ($data ? $data->{methods} : undef, $err);
}

# `$void_effect_call` means "void AND effectful" where it is set at the top: a
# genuinely void call is pinned on control and pushes nothing, and those are the
# same decision. The GLOBAL-STATE widening then sets the SAME flag for a
# NON-void require/dofile -- to borrow the control pinning, which a global-state
# op needs in any context -- and inherited the value suppression with it.
#
# So `require "x.pm" or die $@` pushed no LHS and the `or` handler's
# unconditional pop underflowed:
#
#     INTERNAL ERROR translating main::f: Stack underflow at StackSim.pm line 25
#
# An INTERNAL ERROR is the worse category: it fires before any honest refusal
# could and names StackSim, sending the reader after a simulator bug.
#
# NOT a dofile problem -- `require ... or die` fails identically. perl's own
# t/comp/require.t has `sub dofile { do "bleah.do" or die $@ }`, which is why it
# surfaced there first.
subtest 'a non-void require/dofile yields its value' => sub {
    for my $case (
        ['do FILE',  'sub f { do "x.do" or die $@ } print "ok";'],
        ['require',  'sub f { require "x.pm" or die $@ } print "ok";'],
    ) {
        my ($name, $src) = $case->@*;
        my (undef, $err) = translate($src);
        unlike $err, qr/INTERNAL ERROR/, "$name: does not crash" or diag $err;
        unlike $err, qr/Stack underflow/, "$name: no underflow";
    }
};

# THE EFFECT MUST SURVIVE TOO. The whole reason the global-state widening
# exists is that a require dropped off the control chain is deleted by DCE --
# `require Foo; Foo->new` would call a method on a package nothing loaded. So
# the value fix must not cost the control edge.
subtest 'the effect is still pinned on control' => sub {
    my ($m, $err) = translate('sub f { require "x.pm" or die $@ } print "ok";');
    ok defined $m && $m->{'main::f'}, 'it translates' or diag($err), return;

    my ($call) = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') =~ /require|dofile/
    } $m->{'main::f'}{nodes}->@*;
    ok defined $call, 'the require is in the graph -- not DCEd away' or return;
    ok exists $call->{control_in},
        'and it is pinned on the control chain';
};

# A VOID one still pushes nothing: that is the case the flag was written for
# and it must not regress.
subtest 'a void require pushes nothing' => sub {
    my ($m, $err) = translate('sub f { require "x.pm"; 1 } print "ok";');
    ok defined $m && $m->{'main::f'}, 'it translates' or diag($err), return;
    unlike $err, qr/INTERNAL ERROR/, 'no crash';

    my ($call) = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') =~ /require|dofile/
    } $m->{'main::f'}{nodes}->@*;
    ok defined $call, 'the require is still in the graph' or return;
    ok exists $call->{control_in}, 'still pinned on control';
};

done_testing;
