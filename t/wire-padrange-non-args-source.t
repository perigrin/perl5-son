# ABOUTME: A padrange LHS whose RHS is not @_ must still bind its targets.
# ABOUTME: Skipping it made aassign find an empty mark and drop the statement.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graph_of ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    my ($k) = grep { /::c$/ } keys $data->{methods}->%*;
    return $k ? $data->{methods}{$k} : undef;
}

# `my ($a,$b) = EXPR` fuses its LHS into a padrange. The handler recognised
# only the `my (...) = @_` form (OPf_SPECIAL, flags 128) and let every other
# shape fall through to OpMap, which declares padrange SKIP -- so the targets
# were never pushed, aassign found an EMPTY MARK, and the whole statement
# vanished with no diagnostic at all.
#
# Measured on `sub c { my ($p,$f,$l) = caller; return $l }`: the graph was
# Start, Constant undef, Return. No Call, no Assign, no PadAccess -- the sub
# body was gone.
# TODO: not fixed. Diagnosed to the point below but no fix landed; the two
# assertions here are the pin.
my $todo = todo 'a non-@_ list assign still drops its statement';
subtest 'a non-@_ list assign keeps its statement' => sub {
    my $g = graph_of(qq{sub c { my (\$p, \$f, \$l) = caller; return \$l }\nc();\n});
    ok defined $g, 'the sub translates' or return;

    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'Call' } @ops), 'the caller Call survives'
        or diag "ops = @ops";
    ok scalar(grep { $_ eq 'Assign' } @ops), 'and the Assign is built'
        or diag "ops = @ops";
};

# The same shape over other no-argument list builtins, which all lost their
# bodies the same way.
subtest 'the other list builtins keep theirs too' => sub {
    for my $call ('localtime', 'times') {
        my $g = graph_of(qq{sub c { my (\$a, \$b) = $call; return \$b }\nc();\n});
        ok defined $g, "$call: the sub translates" or next;
        my @ops = map { $_->{op} } $g->{nodes}->@*;
        ok scalar(grep { $_ eq 'Assign' } @ops), "$call: the Assign is built"
            or diag "ops = @ops";
    }
};

# `my (...) = @_` must not regress. Measured, this shape builds an Assign
# over an ArgsSource rather than taking padrange's own @_-element path --
# which one applies depends on the surrounding statement, and both are
# correct. What matters is that the Assign exists at all.
undef $todo;

subtest 'the @_ form is unchanged' => sub {
    my $g = graph_of(qq{sub c { my (\$a, \$b) = \@_; return \$b }\nc(1,2);\n});
    ok defined $g, 'the sub translates' or return;
    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'Assign' } @ops),
        'the Assign is built' or diag "ops = @ops";
    ok scalar(grep { $_ eq 'ArgsSource' || $_ eq 'Subscript' } @ops),
        'and @_ is its source' or diag "ops = @ops";
};

done_testing;
