# ABOUTME: A conditional eval's value outlives the block it is produced in.
# ABOUTME: A `my` at its own position scoped it to the arm and later reads saw undef.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

sub run_src ($src) {
    my $file = __FILE__ . ".run.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $file 2>&1);
    unlink $file;
    return $out;
}

sub emit ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return SoN::Deparse->new->render($data);
}

sub round_trips ($name, $src) {
    my $emitted = emit($src);
    ok defined $emitted, "$name: it renders" or return;
    is run_src($emitted), run_src($src), "$name: it agrees with perl"
        or diag "emitted:\n$emitted";
}

# `A and B and C` renders as NESTED IFS -- each eval happening only if the
# previous succeeded -- but the final expression reads ALL of them. A `my` at
# each eval's own position scoped it to its arm:
#
#     my $eval10 = eval("1");
#     if ($eval10) { my $eval20 = eval("2"); }
#     ... $eval20 ...        <- out of scope, undef
#
# comp/colon.t is this shape 25 times over; every one of its first 11 tests
# came out `not ok` because each later eval read an undef. It ROUND-TRIPS now.
#
# Declared at the top and assigned in place, the same mechanism a join Phi
# uses and for the same reason: the value outlives the branch producing it.
subtest 'a conditional eval is readable after its block' => sub {
    round_trips 'a chain of two',
        qq{print((eval "1" and eval "2") ? "y\\n" : "n\\n");\n};
    round_trips 'a chain of four',
        qq{print(((eval "1" and eval "2") and not eval "0") ? "y\\n" : "n\\n");\n};
};

# An unconditional eval must keep working -- it was never scoped wrongly.
subtest 'a plain eval is unchanged' => sub {
    round_trips 'a block eval',  qq{my \$r = eval { 42 };\nprint "\$r\\n";\n};
    round_trips 'a string eval', qq{my \$r = eval "2+3";\nprint "\$r\\n";\n};
    round_trips 'one that dies',
        qq{my \$r = eval { die "x\\n"; 1 };\nprint defined \$r ? "def\\n" : "undef\\n";\n};
};

done_testing;
