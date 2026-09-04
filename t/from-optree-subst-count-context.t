# ABOUTME: A destructive s/// in scalar context yields the match COUNT, not the subject.
# ABOUTME: Zero matches is "" and not 0, so the result is Str, never Boolean or Int.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graph_of ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) };
    return ($data ? $data->{methods}{'main::__PROGRAM__'} : undef, $err);
}

sub subst_nodes ($g) {
    return grep { $_->{op} eq 'RegexSubst' } $g->{nodes}->@*;
}

# Measured on 5.42.0. The destructive form returns a COUNT:
#
#     "aaa" =~ s/a/b/g   ->  3     an Int
#     "xxx" =~ s/a/b/g   ->  ""    the EMPTY STRING, defined and false
#     "aaa" =~ s/a/b/    ->  1
#
# Zero matches is "" rather than 0, so `defined` does not separate the two
# cases -- only truth does. Int-or-empty-string is Str in this lattice, and
# Boolean is NOT available for it: %PARENTS has Boolean => Scalar rather than
# Boolean => Str, on a measured two-factor subtyping test. Stamping the count
# Boolean would claim something perl contradicts.
#
# /r is a different operation, not a different context. It yields the modified
# COPY and never a count, and leaves the target alone:
#
#     "aaa" =~ s/a/b/gr  ->  "bbb"    target still "aaa"
#     "xxx" =~ s/a/b/gr  ->  "xxx"    unchanged copy, still a string
subtest 'destructive s/// in scalar context is a Str count' => sub {
    my ($g, $err) = graph_of(qq{my \$a = "aaa";\nmy \$n = (\$a =~ s/a/b/g);\nprint qq{\$n\\n};\n});
    ok defined $g, 'lowers rather than refusing' or do { diag $err; return };

    my ($s) = subst_nodes($g);
    ok defined $s, 'the RegexSubst is in the graph' or return;
    is $s->{stamp}, 'Str', 'the count result is stamped Str';
};

subtest 's///r keeps the rewritten-subject stamp' => sub {
    my ($g, $err) = graph_of(qq{my \$b = "aaa";\nmy \$r = (\$b =~ s/a/b/gr);\nprint qq{\$r\\n};\n});
    ok defined $g, 'lowers' or do { diag $err; return };

    my ($s) = subst_nodes($g);
    ok defined $s, 'the RegexSubst is in the graph' or return;
    is $s->{stamp}, 'Str', 'the rewritten subject is Str';
    like $s->{fields}{flags}, qr/r/, 'and it is the /r form';
};

# Void context discards the result, so no count is produced and the existing
# rewritten-subject path stays correct. This is the case that always worked;
# it is here so lowering the count form cannot regress it.
subtest 'void-context s/// is unaffected' => sub {
    my ($g, $err) = graph_of(qq{my \$a = "aaa";\n\$a =~ s/a/b/g;\nprint qq{\$a\\n};\n});
    ok defined $g, 'lowers' or do { diag $err; return };
    my ($s) = subst_nodes($g);
    ok defined $s, 'the RegexSubst is in the graph';
};

# THE SECOND CONSTRUCTION SITE. s/// inside a loop body is built by a separate
# walker, and it lowered the count form with just the RegexSubst -- so `$n` got
# the substituted STRING rather than the count. Same defect, different site;
# the first fix did not reach it.
#
#     my @w = ("aaa","xxx");
#     for my $s (@w) { my $n = ($s =~ s/a/b/g); ... }
#       perl: n=[3] s=bbb    then    n=[] s=xxx
#
# The zero-match iteration is what makes Str the only honest stamp: "" and not 0.
subtest 's/// count in a loop body also lowers to a count' => sub {
    my ($g, $err) = graph_of(
        qq{my \@w = ("aaa","xxx");
for my \$s (\@w) {
  my \$n = (\$s =~ s/a/b/g);
  print qq{[\$n]\\n};
}
});
    ok defined $g, 'lowers' or do { diag $err; return };

    my ($c) = grep { $_->{op} eq 'RegexSubstCount' } $g->{nodes}->@*;
    ok defined $c, 'the loop-body count produces a RegexSubstCount' or return;
    is $c->{stamp}, 'Str', 'stamped Str';
};

done_testing;
