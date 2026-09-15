# ABOUTME: A sub in a non-main package is emitted into that package.
# ABOUTME: Flattening xyz::new to xyz__new defined it in main and broke dispatch.

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

# `xyz::new` is already a legal fully-qualified name, but _sub_ident flattened
# every `::` to `__` -- so the sub was DEFINED in main:: as `xyz__new` while
# the CALL site still emitted `xyz->new()`, which dispatches to the real `xyz`
# package and finds nothing. Measured on comp/package.t, where five packages
# collapsed into one and `xyz->new` died with "Can't locate object method".
#
# The mangling exists for names perl cannot spell -- an anon sub arrives as
# `main::__PROGRAM__::__ANON__:1:2` -- so the test is whether every segment is
# an identifier, not whether a `::` is present.
subtest 'a package sub keeps its package' => sub {
    round_trips 'a method',
        qq{package xyz;\nsub new { bless [] }\npackage main;\nmy \$o = xyz->new;\nprint ref(\$o), "\\n";\n};
    round_trips 'a function',
        qq{package xyz;\nsub hi { "hi" }\npackage main;\nprint xyz::hi(), "\\n";\n};
    round_trips 'a nested package',
        qq{package A::B;\nsub w { "deep" }\npackage main;\nprint A::B::w(), "\\n";\n};
};

# One-argument `bless` blesses into the CURRENT package, which the graph does
# not record -- perl resolves it at compile time. The sub's own name carries
# it, so the class is named explicitly and the emitted program no longer
# depends on which package the emitted file happens to be in.
subtest 'a one-argument bless names its class' => sub {
    round_trips 'in a package',
        qq{package xyz;\nsub new { bless [] }\npackage main;\nmy \$o = xyz->new;\nprint ref(\$o), "\\n";\n};
    round_trips 'in main',
        qq{sub mk { bless {} }\nmy \$o = mk();\nprint ref(\$o), "\\n";\n};
    round_trips 'with an explicit class',
        qq{package xyz;\nsub new { bless [], shift }\npackage main;\nmy \$o = xyz->new;\nprint ref(\$o), "\\n";\n};
};

# A main:: sub and an anon sub must not regress.
subtest 'main and anonymous subs are unchanged' => sub {
    round_trips 'a main sub', qq{sub f { 42 }\nprint f(), "\\n";\n};
    round_trips 'an anon sub', qq{my \$c = sub { 7 };\nprint \$c->(), "\\n";\n};
};

done_testing;
