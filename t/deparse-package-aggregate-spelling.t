# ABOUTME: A package aggregate's symbol already carries its sigil.
# ABOUTME: Adding a second gave @@main::EST, and `my` on it is a syntax error.

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

# A PAD aggregate records a bare name (`EST`) beside sigil `@`. A PACKAGE one
# records the whole qualified spelling (`@main::EST`) AND sets the sigil, so
# concatenating both gave `@@main::EST`. Measured on `our @EST = ("foo","bar")`,
# and base/lex.t's emitted program died at compile time on exactly that.
#
# `my @main::EST` is a second error in the same line -- "can't be in a
# package" -- and a package variable needs no declaration at all.
subtest 'a package aggregate spells itself once' => sub {
    round_trips 'array',
        qq{our \@EST = ("foo","bar");\nprint "\@EST\\n";\n};
    round_trips 'hash',
        qq{our \%H = (a=>1, b=>2);\nprint "\$H{a}\$H{b}\\n";\n};
};

# An ELEMENT takes `$` whatever the container's sigil, so the symbol's own
# sigil must be stripped rather than prefixed: `$@main::E[0]` does not parse.
subtest 'an element of a package aggregate takes one sigil' => sub {
    round_trips 'array element',
        qq{our \@E = ("p","q");\nprint "\$E[1]\\n";\n};
    round_trips 'hash element',
        qq{our \%H = (k=>"v");\nprint "\$H{k}\\n";\n};
};

# A SLICE always takes `@`, so the same stripping applies there.
subtest 'a slice of a package aggregate takes one sigil' => sub {
    round_trips 'array slice',
        qq{our \@E = ("p","q","r");\nprint "\@E[0,2]\\n";\n};
    round_trips 'hash slice',
        qq{our \%H = (a=>1, b=>2);\nprint "\@H{'a','b'}\\n";\n};
};

# The pad forms must not regress: their symbol is bare and still needs `my`.
subtest 'a pad aggregate is unchanged' => sub {
    round_trips 'array',   qq{my \@a = (1,2,3);\nprint "\@a\\n";\n};
    round_trips 'hash',    qq{my \%h = (x=>9);\nprint "\$h{x}\\n";\n};
    round_trips 'element', qq{my \@a = (5,6);\nprint "\$a[0]\\n";\n};
    round_trips 'slice',   qq{my \@a = ("x","y","z");\nprint "\@a[0,2]\\n";\n};
};

done_testing;
