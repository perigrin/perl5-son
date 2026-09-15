# ABOUTME: A destructive s/// on a package scalar must store its result back.
# ABOUTME: Without the store the substitution is computed and then dropped.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graph_of ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return $data->{methods}{'main::__PROGRAM__'};
}

# `our $g = "aaa"` binds the scope key to the Constant "aaa". _subst_target
# then returns THAT as the target, so _entry_store's EntryDef check rejected
# it and no write-back was emitted. The substitution was left floating,
# consumed by nobody. Measured:
#
#     our $g="aaa"; $g =~ s/a/b/; $g =~ s/b/c/; print "$g\n";
#       perl  : caa
#       before: aaa -- both RegexSubst nodes orphaned, the print reading the
#               memory version from the initialiser
#
# This is the same fault the $_ branch below it already fixes, and the fix is
# the same: the bound VALUE is the right operand to read, but the store needs
# the NAME, so rebuild an EntryDef beside it.
subtest 'a package s/// stores its result back' => sub {
    my $g = graph_of(qq{our \$g = "aaa";\n\$g =~ s/a/b/;\nprint qq{\$g\\n};\n});
    ok defined $g, 'it translates' or return;

    my %by_id = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($subst) = grep { $_->{op} eq 'RegexSubst' } $g->{nodes}->@*;
    ok defined $subst, 'the substitution is in the graph' or return;

    # The store is an EntryWrite whose VALUE operand (input 1) is the subst.
    # Counting EntryWrites is not enough: `our $g = "aaa"` emits one of its
    # own, so a bare count passes with the substitution still dropped.
    my @writes = grep { $_->{op} eq 'EntryWrite'
                        && ($_->{inputs}[1] // -1) == $subst->{id} }
                 $g->{nodes}->@*;
    is scalar(@writes), 1,
        'exactly one EntryWrite names the substitution as its value';

    my $name = $by_id{ $writes[0]{inputs}[0] // -1 };
    is $name && $name->{op}, 'EntryDef',
        'the store names the variable, not a value';
    is $name && $name->{fields}{symbol}, 'g', 'and it is $g';
};

# Two substitutions over the same package scalar form a chain: the second
# reads what the first wrote. Both naming the initialiser's memory version is
# a FORK, and control_in is a total order over effects.
subtest 'chained package substitutions thread memory in order' => sub {
    my $g = graph_of(qq{our \$g = "aaa";\n\$g =~ s/a/b/;\n\$g =~ s/b/c/;\nprint qq{\$g\\n};\n});
    ok defined $g, 'it translates' or return;

    my @subst = grep { $_->{op} eq 'RegexSubst' } $g->{nodes}->@*;
    is scalar(@subst), 2, 'both substitutions are in the graph' or return;

    my %writes;
    for my $w (grep { $_->{op} eq 'EntryWrite' } $g->{nodes}->@*) {
        $writes{ $w->{inputs}[1] // -1 } = $w;
    }
    ok $writes{ $subst[0]{id} }, 'the first substitution is stored back';
    ok $writes{ $subst[1]{id} }, 'the second substitution is stored back';

    # The second subst must READ the first one's store, not the initialiser.
    my $second_mem = $subst[1]{inputs}[-1];
    is $second_mem, $writes{ $subst[0]{id} }{id},
        'the second substitution supersedes the first store, not the initialiser';
};

done_testing;
