# ABOUTME: `@_ = LIST` assigns into the argument array, which is an lvalue.
# ABOUTME: ArgsSource was missing from the target allow-list, so it refused.

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
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
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

# The Assign branch walks its leading inputs while they are targets, keyed on
# a list of node kinds: PadAccess, EntryDef, Subscript, PostfixDeref. An
# ArgsSource is none of those, so `@_ = ("a","b")` reported ZERO targets and
# refused -- although ArgsSource already renders as `@_`, which is an
# ordinary lvalue.
#
# An allow-list fails asymmetrically: the missing name does not announce
# itself, it just makes a valid case disappear. base/lex.t reaches this
# through `@_ = map {...} LIST` at file scope.
subtest 'the argument array is an assignable target' => sub {
    round_trips 'from a list',
        qq{\@_ = ("a","b");\nprint "\@_\\n";\n};
    round_trips 'from a map',
        qq{\@_ = map { "rhu\$_" } "barb2";\nprint "\@_\\n";\n};
    round_trips 'from a map over a number',
        qq{\@_ = map { \$_ + 1 } 1;\nprint "\@_\\n";\n};
};

# An ArgsSource is ALSO the ordinary right-hand side of `my (...) = @_`, and
# both spell the same node kind. Adding it to the target list outright made
# this consume its own RHS -- three inputs, all "targets", no values left --
# and base/lex.t's `sub T` refused. Position is what separates them.
subtest 'the argument array is still a source on the right' => sub {
    round_trips 'bound to two lexicals',
        qq{sub T { my (\$a, \$b) = \@_; print "\$a \$b\\n" }\nT("x","y");\n};
    round_trips 'bound to one lexical',
        qq{sub U { my (\$a) = \@_; print "\$a\\n" }\nU("z");\n};
};

done_testing;
