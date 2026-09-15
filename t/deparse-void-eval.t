# ABOUTME: A void-context block eval still protects its body.
# ABOUTME: Having no value Phi is not the same as not being an eval.

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

# `eval { die "x\n"; };` discards its result and reads only $@ afterwards, so
# there is no value for a Phi to merge. _is_eval_join required one, so the
# Region was not recognised as an eval at all and the emitted program had NO
# eval -- the die propagated and killed it:
#
#     eval { die "x\n" }; print "caught\n" if $@; print "end\n";
#       perl : caught / end
#       emit : died with "x", printing neither
#
# That is a silent miscompile of exception handling. The Region names its
# `eval_entry` on the wire for exactly this, so the field decides rather than
# a Phi a void eval never has.
subtest 'a void eval protects its body' => sub {
    round_trips 'a bare die',
        qq{eval { die "x\\n"; };\nprint "caught\\n" if \$\@;\nprint "end\\n";\n};
    round_trips 'a call that dies',
        qq{sub boom { die "b\\n" }\neval { boom(); };\nprint "caught\\n" if \$\@;\nprint "end\\n";\n};
    round_trips 'a method that does not exist',
        qq{my \$o = bless {}, "N";\neval { \$o->nope; };\nprint "caught\\n" if \$\@;\nprint "end\\n";\n};
    round_trips 'a body that does not die',
        qq{eval { my \$x = 1; };\nprint "ok\\n";\n};
};

# The valued forms must not regress: they have a Phi and take the old path.
subtest 'a valued eval still yields its value' => sub {
    round_trips 'a block eval',
        qq{my \$r = eval { 42 };\nprint "\$r\\n";\n};
    round_trips 'a block eval that dies',
        qq{my \$r = eval { die "z\\n"; 1 };\nprint defined \$r ? "def\\n" : "undef\\n";\n};
    round_trips 'a string eval',
        qq{my \$r = eval "2+3";\nprint "\$r\\n";\n};
};

done_testing;
