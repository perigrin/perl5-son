# ABOUTME: caller reads the call stack, so T1 records it in every context.
# ABOUTME: The deparser is a T2 and refuses it -- a deparsed program has a different stack.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

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

sub calls_named ($g, $want) {
    return grep {
        ($_->{op} // '') eq 'Call'
            && (($_->{fields} // {})->{name} // '') eq $want
    } $g->{nodes}->@*;
}

# `caller` READS THE CALL STACK -- state outside the expression -- so WHERE it
# happens is part of what it means. T1's job is to say truthfully what the
# program DOES; a backend that cannot lower a stack read still needs to be
# TOLD there was one, and it cannot be told what T1 did not record.
#
# Nothing pinned it, so in any VALUE context its Call had no consumer once the
# surrounding list-assign failed to bind, and DCE removed it:
#
#     sub c { my ($p,$f,$l) = caller; return $l }
#       before: Start, Constant undef, Return -- the Call was gone
#
# The VOID form already survived, which is what makes this a CONTEXT hole
# rather than a missing op. Same gap %HANDLE_READ_BUILTIN exists for: "a read
# whose value is BOUND is not void, so it was never pinned."
subtest 'caller is recorded in every context' => sub {
    for my $case (
        [ 'a list assign', 'sub c { my ($p, $f, $l) = caller; return $l }' ],
        [ 'a scalar bind', 'sub c { my $x = caller; return 1 }' ],
        [ 'void',          'sub c { caller(); return 1 }' ],
    ) {
        my ($what, $src) = $case->@*;
        my $g = sub_graph("$src\nc();\n", 'c');
        ok defined $g, "$what: the sub translates" or next;

        my @caller = calls_named($g, 'caller');
        ok scalar(@caller), "$what: the Call is in the graph"
            or diag 'ops = ' . join(' ', map { $_->{op} } $g->{nodes}->@*);
        ok @caller && defined $caller[0]{control_in},
            "$what: and it is pinned, so nothing may drop it";
    }
};

# NOT ASSERTED HERE: the Call's STAMP. `caller` is stamped Scalar even in list
# context, because TypeLibrary has no row for it and nothing reads $op->flags
# at the construction site. That is a real gap -- TypeLibrary names the remedy
# under WHAT IS DELIBERATELY ABSENT -- but it is a TYPING question, separate
# from whether the operation is RECORDED, and this file is about the latter.
# Left unasserted rather than pinned, because no attempt at it survives here.

# THE DEPARSER IS A T2 CONSUMER, and it refuses only the shape it cannot
# spell. A blanket refusal cost NINE corpus files, and measurement said it was
# refusing the wrong thing: with it removed, comp/our.t dies on TIESCALAR and
# comp/opsubs.t differs from test 2 -- neither because of `caller`. In four of
# them it sits in a `sub failed {...}` diagnostic emitting ZERO lines on a
# passing run, where the emitted program agreed with perl exactly.
#
# What cannot round-trip is a caller BOUND TO A LIST: a pinned Call binds to a
# scalar `$effN` at its chain position, so `my ($p,$f,$l) = caller` becomes
# `my $eff1 = caller(); my ($p,$f,$l) = ($eff1)` and two targets take undef.
# That is a wrong ANSWER, not merely a different stack.
subtest 'the deparser refuses a caller bound to a list' => sub {
    my $file = __FILE__ . ".d.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh qq{sub c { my (\$p, \$f, \$l) = caller; return \$p }\nprint c(), "\\n";\n};
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return;

    my $d = SoN::Deparse->new;
    is $d->render($data), undef, 'it refuses to render';
    like $d->gap, qr/bound to a list/, 'and the refusal names the reason';
};

# The renderable shapes must keep rendering. They report THIS program's stack
# rather than the original's -- the honest T2 answer for a construct whose
# meaning is its frame -- and where nothing observes the difference, the
# oracle agrees.
subtest 'the other shapes still render' => sub {
    for my $case (
        [ 'a scalar bind', qq{sub c { my \$x = caller; return \$x }\nprint c(), "\\n";\n} ],
        [ 'void',          qq{sub c { caller(); return "ok" }\nprint c(), "\\n";\n} ],
        [ 'a diagnostic that never runs',
          qq{sub failed { my \@c = caller(0); print "# at \$c[1]\\n" }\nprint "ok\\n";\n} ],
    ) {
        my ($what, $src) = $case->@*;
        my $file = __FILE__ . ".r.$$.pl";
        open my $fh, '>', $file or die $!;
        print $fh $src;
        close $fh;
        my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
        my $want = qx($^X $file 2>&1);
        unlink $file;
        my $data = eval { JSON::PP->new->decode($out) } or next;

        my $d = SoN::Deparse->new;
        my $rendered = $d->render($data);
        ok defined $rendered, "$what: it renders" or next;

        my $rf = __FILE__ . ".e.$$.pl";
        open my $eh, '>', $rf or die $!;
        print $eh $rendered;
        close $eh;
        my $got = qx($^X $rf 2>&1);
        unlink $rf;
        is $got, $want, "$what: and it agrees with perl";
    }
};

done_testing;
