# ABOUTME: the wire says, as a fact of the program, whether perl runs it with
# ABOUTME: -w / $^W on, -W (every warning on) or -X (every warning off).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub wire_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    return eval { JSON::PP->new->decode($j) };
}

# A __WARN__ handler is called for perl's own warnings, and whether perl
# raises any of them where no `use warnings` is in scope is the -w switch
# (`#!perl -w`) or $^W: nothing in the graph said which.
for my $case (
    [ 'no switch',          qq{print "x\\n";\n},                         { on => 0, all_on => 0, all_off => 0 } ],
    [ '#!perl -w',          qq{#!perl -w\nprint "x\\n";\n},              { on => 1, all_on => 0, all_off => 0 } ],
    [ 'BEGIN { \$^W = 1 }', qq{BEGIN { \$^W = 1 }\nprint "x\\n";\n},     { on => 1, all_on => 0, all_off => 0 } ],
    [ '#!perl -W',          qq{#!perl -W\nprint "x\\n";\n},              { on => 1, all_on => 1, all_off => 0 } ],
    [ '#!perl -X',          qq{#!perl -X\nprint "x\\n";\n},              { on => 0, all_on => 0, all_off => 1 } ],
    [ '#!perl -w -X',       qq{#!perl -w -X\nprint "x\\n";\n},           { on => 0, all_on => 0, all_off => 1 } ],
) {
    my ($name, $src, $want) = @$case;
    my $w = wire_of($src);
    ok $w && ref $w->{dowarn} eq 'HASH', "$name: the wire says" or next;
    is { map { ( $_ => $w->{dowarn}{$_} ? 1 : 0 ) } keys $w->{dowarn}->%* }, $want, "$name: as perl runs it";
    ok JSON::PP::is_bool( $w->{dowarn}{$_} ), "$name: $_ is a boolean" for sort keys %$want;
}

done_testing;
