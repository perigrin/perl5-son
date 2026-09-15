# ABOUTME: A counted s/// that also stores back must run exactly once.
# ABOUTME: Two consumers over one substitution rendered it twice, losing the count.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

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

sub run_perl ($src) {
    my $file = __FILE__ . ".run.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $file 2>&1);
    unlink $file;
    return $out;
}

# `my $n = ($s =~ s/a/b/g)` builds ONE RegexSubst with TWO consumers: the
# EntryWrite that stores the modified string back, and the RegexSubstCount
# that takes the number. Each rendered the substitution on its own, so the
# emitted program ran the s/// twice -- and the second pass saw `bbb`, matched
# nothing, and counted zero.
#
#     perl  : 3 bbb
#     before: " bbb"   right string, count silently lost
#
# The destructive form does both jobs at once, so the store emits it bound and
# the count reads that binding.
subtest 'a counted, stored substitution runs once' => sub {
    my $src = qq{our \$s = "aaa";\nmy \$n = (\$s =~ s/a/b/g);\nprint qq{\$n \$s\\n};\n};

    my $emitted = emit($src);
    ok defined $emitted, 'it renders' or return;

    # Exactly one s/// in the output. Two is the defect, whatever they say.
    my $count = () = $emitted =~ /s\{/g;
    is $count, 1, 'the substitution appears once in the emitted program'
        or diag $emitted;

    is run_perl($emitted), run_perl($src),
        'and the emitted program agrees with perl';
};

# Without a store there is nothing to double up, but the count must still be a
# number rather than the substituted string.
subtest 'a count with no other reader still counts' => sub {
    my $src = qq{our \$s = "axbxc";\nmy \$n = (\$s =~ s/x/-/g);\nprint qq{\$n\\n};\n};
    my $emitted = emit($src);
    ok defined $emitted, 'it renders' or return;
    is run_perl($emitted), run_perl($src), 'it agrees with perl';
};

# /r is the non-destructive form: it yields a new string and leaves the source
# alone, so it must NOT be turned into an in-place substitution.
subtest 'the /r form does not mutate its subject' => sub {
    my $src = qq{our \$s = "ab";\nmy \$t = (\$s =~ s/a/X/r);\nprint qq{\$s \$t\\n};\n};
    my $emitted = emit($src);
    ok defined $emitted, 'it renders' or return;
    is run_perl($emitted), run_perl($src), 'it agrees with perl';
};

done_testing;
