# ABOUTME: `undef` is a legal placeholder in a list-assign target list.
# ABOUTME: Treating it as a value took the whole list and emitted nothing.

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

# `my (undef, $b) = @_` discards the first value -- a common idiom, and
# comp/parser.t uses it as `my (undef, $f, $l) = caller`. It reaches the wire
# as an undef Constant, which is not a slot, so the target walk stopped at it.
#
# A LEADING undef merely refused. A TRAILING or MIDDLE one was worse: the walk
# stopped before any target, so the whole list read as VALUES and the emitted
# program printed nothing at all.
#
#     sub f { my ($a, undef, $c) = @_; print "$a$c" } f(1,2,3)
#       perl : 13
#       emit : (nothing)
subtest 'undef is a target placeholder, not a value' => sub {
    round_trips 'first',
        qq{sub f { my (undef, \$b) = \@_; print "\$b\\n" }\nf(1,2);\n};
    round_trips 'middle',
        qq{sub f { my (\$a, undef, \$c) = \@_; print "\$a\$c\\n" }\nf(1,2,3);\n};
    round_trips 'last',
        qq{sub f { my (\$a, undef) = \@_; print "\$a\\n" }\nf(1,2);\n};
};

# A list with no undef must not regress, and neither must a bare `my $x`,
# whose single undef Constant is its VALUE rather than a placeholder.
subtest 'the ordinary forms are unchanged' => sub {
    round_trips 'no undef',
        qq{sub f { my (\$a, \$b) = \@_; print "\$a\$b\\n" }\nf(1,2);\n};
    round_trips 'a bare my',
        qq{my \$x;\nprint defined(\$x) ? "d\\n" : "u\\n";\n};
};

done_testing;
