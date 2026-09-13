# ABOUTME: s/// on a package scalar must bind the real variable, not $_.
# ABOUTME: The target is an EntryDef from the GV on the stack, keyed like every other read.

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

# `$main::g =~ s/a/b/` has no pad targ, because the destination is a GV on the
# stack. Keying a missing targ as '$main::_' bound the wrong variable and the
# substitution vanished from the graph entirely:
#
#     our $g = "aaa"; $main::g =~ s/a/b/g; print "g=$main::g";
#       perl  : g=bbb
#       before: no RegexSubst anywhere -- printed the folded "g=aaa"
#
# The GV is right there under the op, so the target is an ordinary EntryDef
# keyed the way every package read is keyed. It refused only because package
# scalars had no store to rebind through; EntryWrite supplies that now.
subtest 'a package-target s/// binds the real variable' => sub {
    my $g = graph_of(qq{our \$g = "aaa";\n\$main::g =~ s/a/b/g;\nprint qq{g=\$main::g\\n};\n});
    ok defined $g, 'it translates' or return;

    my ($subst) = grep { $_->{op} eq 'RegexSubst' } $g->{nodes}->@*;
    ok defined $subst, 'the substitution is in the graph, not dropped' or return;

    # The store is what proves the right variable was named. At program level
    # perl has already folded $g to its constant, so the subst's OPERAND is a
    # Constant rather than an EntryDef -- asserting on the operand would be
    # testing the constant folder, not the binding.
    my ($write) = grep { $_->{op} eq 'EntryWrite' } $g->{nodes}->@*;
    ok defined $write, 'the substitution stores back' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my $dest = $by{ $write->{inputs}[0] };
    is $dest->{op}, 'EntryDef', 'into an EntryDef';
    is $dest->{fields}{symbol}, 'g', 'naming g, not _';
};

# The store exists so another sub can see the substitution. Without it, peek()
# reads a value the subst never reached:
#
#     our $g = "aaa";
#     sub mangle { $main::g =~ s/a/b/g }
#     sub peek   { return $main::g }
#     mangle(); print peek();
#       perl : bbb
#       before: main::mangle held the RegexSubst but NO EntryWrite
subtest 'the write is visible to another sub' => sub {
    my $file = __FILE__ . ".tmp2.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh qq{our \$g = "aaa";
sub mangle { \$main::g =~ s/a/b/g }
sub peek { return \$main::g }
mangle();
print peek(), qq{\n};
};
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or do { fail 'translates'; return };

    my @mangle = map { $_->{op} } $data->{methods}{'main::mangle'}{nodes}->@*;
    ok scalar(grep { $_ eq 'EntryWrite' } @mangle),
        'the writing sub emits a store' or diag "mangle: @mangle";

    my ($ed) = grep { $_->{op} eq 'EntryDef' } $data->{methods}{'main::peek'}{nodes}->@*;
    ok defined $ed && scalar($ed->{inputs}->@*),
        'and the reading sub reads through memory';
};

# $_ must keep working -- it is the other thing a missing targ means.
subtest 'an implicit $_ s/// still binds $_' => sub {
    my $g = graph_of(qq{for ("aaa") {\n  s/a/b/g;\n  print qq{\$_\\n};\n}\n});
    ok defined $g, 'it translates' or return;
    my ($subst) = grep { $_->{op} eq 'RegexSubst' } $g->{nodes}->@*;
    ok defined $subst, 'the substitution is in the graph';
};

done_testing;
