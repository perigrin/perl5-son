# ABOUTME: a call to a sub the graph does not contain cannot be rendered.
# ABOUTME: emitting it anyway produces a program that dies at runtime.
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;
use SoN::Deparse;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

# THE DEFECT. A sub whose body the producer refuses is absent from the graph,
# but the CALLSITE stays -- it is in __PROGRAM__, which translated fine. The
# deparser rendered the call regardless, so the emitted program called a sub
# that was never defined:
#
#     Undefined subroutine &main::test_string called at rs.out.pl line 168.
#
# Measured on base/rs.t, whose test_string/test_record are refused for
# assigning to a glob: perl prints 44 lines, the emitted program printed 2 and
# died. A GAP would have said so; this looked like a successful render.
#
# THE DEPARSER IS A T2 CONSUMER, and refusing what it cannot satisfy is what a
# T2 does. A call it cannot resolve is exactly that case.
subtest 'a call to an absent sub is refused, not emitted' => sub {
    my $file = "$dir/missing.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} <<'SRC';
sub helper { *FH = shift; 1 }
helper(\*STDOUT);
print "after\n";
SRC
    close $fh;

    my $json = qx{$PERL -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null};
    ok length($json), 'the file still produces a graph' or return;
    my $wire = JSON::PP->new->decode($json);

    ok !exists $wire->{methods}{'main::helper'},
        'the glob-assigning sub is absent, as the producer refused it';

    # render() CATCHES the GAP and records it on the object rather than
    # rethrowing, so the reason is read back from ->gap, not from $@.
    my $dp  = SoN::Deparse->new;
    my $out = $dp->render($wire);
    my $why = $dp->gap // '';

    ok !defined($out), 'the deparser refuses rather than rendering the call'
        or diag("emitted:\n$out");
    like $why, qr/not in the graph/, '... saying the callee is absent' or return;
    like $why, qr/helper/, '... naming the sub it cannot call';
};

# A CALL IT CAN SATISFY IS UNCHANGED. The refusal must key on the callee being
# absent, not on there being a call at all.
subtest 'a call to a present sub still renders' => sub {
    my $file = "$dir/present.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} qq{sub helper { return 7 }\nprint helper(), "\\n";\n};
    close $fh;

    my $json = qx{$PERL -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null};
    ok length($json), 'it translates' or return;
    my $wire = JSON::PP->new->decode($json);

    my $out = eval { SoN::Deparse->new->render($wire) };
    ok defined($out), 'and renders' or diag($@), return;
    like $out, qr/helper/, 'the call is still there';

    my $emitted = "$dir/present.out.pl";
    open my $o, '>', $emitted or die; print {$o} $out; close $o;
    is qx{$PERL $emitted 2>&1}, "7\n", 'and the emitted program agrees with perl';
};

done_testing;
