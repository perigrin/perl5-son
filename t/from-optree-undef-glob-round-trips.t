# ABOUTME: `undef *glob` clears the whole symbol-table slot; the emission is the
# ABOUTME: source spelling, so only a CALL to that name afterwards must refuse.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

sub gap_for ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    unlink $file;
    return $err;
}

# undef(EXPR) on an aggregate EMPTIES the container, which `@a = ()` expresses,
# so rv2av/rv2hv lower to an empty literal bound to the name. A GLOB is a
# different operation and must not borrow that lowering -- `undef *foo` clears
# EVERY slot, the code slot with them:
#
#     sub foo {"SUB"} our $foo="S"; our @foo=(1); our %foo=(k=>1);
#     undef(*foo);
#       defined &foo -> no
#       foo()        -> dies, "Undefined subroutine &main::foo called"
#
# THE REFUSAL WAS WIDER THAN THE REASON. It named the code slot -- correctly --
# and then refused every `undef *glob`, including the ones with no later call to
# that name. But the EMISSION is the source spelling and perl does the clearing:
#
#     undef(*main::foo);
#
# so the shape is lowerable, and the operand needs its SIGIL (a bareword `glob`
# Constant emitted `undef(v)`, which perl rejects as "Can't modify constant item
# in undef operator").
#
# What genuinely needs a data edge is only "every LATER CALL to this name now
# dies", because a Call binds its callee by name -- and that hazard requires a
# later call to exist. comp/form_scope.t, the file this refusal blocked, does
# `undef *bar` and never calls `bar` again: the point of the test is that a
# format still works afterwards.
#
# ASSERTED AS ROUND TRIPS, because "it refuses" cannot distinguish a necessary
# refusal from a habitual one.
sub round_trips ($src, $norm = undef) {
    $norm //= sub { shift };
    my $file = __FILE__ . ".rt.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $want = qx($^X $file 2>&1);

    my $json = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($json) } or return ( 0, 'no graph' );
    my $out  = eval { SoN::Deparse->new->render($data) }
        or return ( 0, 'refused: ' . ( $@ // '?' ) );

    my $ef = __FILE__ . ".rt.$$.emit.pl";
    open my $eh, '>', $ef or die $!;
    print $eh $out;
    close $eh;
    my $got = qx($^X $ef 2>&1);
    unlink $ef;
    return ( $norm->($got) eq $norm->($want),
             "got=[$got] want=[$want]\n$out" );
}

for my $case (
    ['glob over a sub'    => qq{sub foo {1}\nundef(*foo);\nprint qq{x\\n};\n}],
    ['glob over an array' => qq{our \@foo=(1);\nundef(*foo);\nprint qq{x\\n};\n}],
    ['glob over a handle' => qq{undef(*STDOUT);\nprint STDERR qq{after\\n};\n}],
) {
    my ($label, $src) = $case->@*;
    my ($ok, $why) = round_trips($src);
    ok $ok, "$label: round-trips" or diag $why;
}

# EVERY SLOT GOES AT ONCE, which is the claim the original refusal rested on and
# is worth asserting rather than assuming. Two slots populated, one `undef *v`,
# both cleared.
subtest 'every slot goes, not just the scalar' => sub {
    my ($ok, $why) = round_trips(
        qq{our \$v="s";\nour \@v=(1,2);\nundef(*v);\n}
      . qq{print defined(\$v) ? "s" : "-", scalar(\@v), qq{\\n};\n});
    ok $ok, 'scalar and array are both cleared' or diag $why;
};

# `undef &NAME` IS THE SAME SHAPE, ONE SLOT NARROWER -- the code slot only, and
# equally well-defined. comp/form_scope.t does `undef &x` at line 110, a few
# lines from the `undef *bar` above, so the two were always met together.
#
# ASSERTED BY CALLING, not by `defined &NAME`: `defined &foo` is emitted as
# `defined("foo")` -- a PRE-EXISTING and independent defect, measured on a
# program with no undef in it at all, where it gives the right answer by
# accident. It would make this subtest pass for the wrong reason.
subtest 'undef on a code slot clears it' => sub {
    my ($ok, $why) = round_trips(
        qq{sub foo {"S"}\nundef &foo;\nprint foo(), qq{\\n};\n},
        sub { ( my $t = shift ) =~ s/ at \S+ line \d+\.?//g; $t } );
    ok $ok, 'a call after it dies as perl does' or diag $why;
};

# THE CALL-AFTER SHAPE IS THE ONE THAT MATTERS, and it does better than refuse:
# the emitted program DIES the way perl does, which is the strongest thing a
# round trip can say about an error case.
subtest 'a call after the undef reproduces perl' => sub {
    # COMPARED WITHOUT THE LOCATION. A die message carries its own filename and
    # line, which an emission can never match -- the assertion is that the same
    # ERROR happens, not that it happens at the same line. Stripping ` at FILE
    # line N.` is what makes this an error comparison rather than a text one.
    my ($ok, $why) = round_trips(
        qq{sub foo {"SUB"}\nundef(*foo);\nprint foo(), qq{\\n};\n},
        sub { ( my $t = shift ) =~ s/ at \S+ line \d+\.?//g; $t } );
    ok $ok, 'the emission dies as perl does' or diag $why;
};

# The aggregate forms still lower -- the refusal above must not have widened.
for my $case (
    ['package array' => qq{our \@a=(1,2);\nundef(\@a);\nprint scalar(\@a), qq{\\n};\n}],
    ['package hash'  => qq{our %h=(k=>1);\nundef(%h);\nprint scalar(keys %h), qq{\\n};\n}],
) {
    my ($label, $src) = $case->@*;
    my $err = gap_for($src);
    unlike $err, qr/GAP:/, "$label: still lowers";
}

done_testing;
