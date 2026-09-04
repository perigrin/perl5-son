# ABOUTME: `undef *glob` clears the whole symbol-table slot, code slot included.
# ABOUTME: No rebind of a single name expresses that, so it must refuse, not lower.

use v5.42.0;
use Test2::V0;

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
# different operation and must not borrow that lowering. Measured:
#
#     sub foo {"SUB"} our $foo="S"; our @foo=(1); our %foo=(k=>1);
#     undef(*foo);
#       defined &foo -> no
#       foo()        -> dies, "Undefined subroutine &main::foo called"
#
# Every slot goes at once, the code slot with them. A Call binds its callee BY
# NAME with no data edge to the glob, so there is no edge a $sim->define could
# travel along to say "every later call to this name now dies". Lowering it as
# an empty literal would bind one name and silently leave the sub callable.
for my $case (
    ['glob over a sub'       => qq{sub foo {1}\nundef(*foo);\nprint qq{x\\n};\n}],
    ['glob over an array'    => qq{our \@foo=(1);\nundef(*foo);\nprint qq{x\\n};\n}],
    ['glob over a handle'    => qq{undef(*STDOUT);\n}],
) {
    my ($label, $src) = $case->@*;
    my $err = gap_for($src);
    like $err, qr/GAP: undef\(EXPR\) on a glob \(rv2gv\)/,
        "$label: refuses with the glob-specific GAP";
    unlike $err, qr/EMPTIES the container/,
        "$label: does not claim the aggregate rationale";
}

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
