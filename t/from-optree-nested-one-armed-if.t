# ABOUTME: A nested ONE-ARMED if carrying a void effect builds real control flow.
# ABOUTME: perl compiles a one-armed if and a statement modifier to the same `and`.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

# Compile $src through B::SoN and return the emitted JSON graph (or die on GAP).
sub graph_for ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err" or die; local $/; <$e> };
    die "GAP: $err" if ($err // '') =~ /GAP:/;
    return $json;
}

sub count_op ($json, $op) {
    my @m = $json =~ /"op"\s*:\s*"\Q$op\E"/g;
    return scalar @m;
}

# A nested one-armed `if` whose body carries a void PRINT. Both the outer and
# the inner branch must become real control flow: two If nodes, not one. With
# only one If the inner guard has been swallowed and its Print fires
# unconditionally (or lands on control that never runs) -- a silent effect
# miscompile, which is why this asserts the count rather than mere lowering.
subtest 'nested one-armed if with a void effect builds BOTH branches' => sub {
    my $json = graph_for(<<'PERL', 'nested_print');
my $x = 1; my $n = 0;
if ($x) { if ($x) { print "in\n"; $n = 7 } }
print "n=$n\n";
PERL
    is count_op($json, 'If'), 2,
        'two source-level ifs produce two If nodes';
    is count_op($json, 'Print'), 2, 'both prints survive';
    ok count_op($json, 'Region') >= 2, 'each branch gets a merge Region';
};

# The scope-free spelling: with no other statement in either block perl
# optimizes the enter/leave pairs away, so the inner `and`'s ->next points PAST
# the outer join. This is the shape that regressed first.
subtest 'nested one-armed if with no scope ops still builds both branches' => sub {
    my $json = graph_for(<<'PERL', 'nested_print_only');
my $x = 1;
if ($x) { if ($x) { print "in\n" } }
print "done\n";
PERL
    is count_op($json, 'If'), 2, 'two If nodes despite the elided scopes';
};

# `elsif` is the spelling that matters most: ordinary code, not a modifier
# idiom, and it lowers to a one-armed `and` in the else position.
subtest 'elsif with a void effect lowers' => sub {
    my $json = graph_for(<<'PERL', 'elsif_effect');
my $x = 2; my $n = 0;
if ($x == 1) { $n = 1 }
elsif ($x == 2) { print "two\n"; $n = 7 }
print "n=$n\n";
PERL
    ok count_op($json, 'If') >= 2, 'the elsif chain builds real branches';
    is count_op($json, 'Print'), 2, 'the guarded print survives';
};

# A nested `die` does not rejoin. It must still be guarded: the arm scan has to
# see the die THROUGH the nested branch, or the outer branch takes the
# value-merge path and the die escapes its guard.
subtest 'nested die is control-guarded' => sub {
    my $json = graph_for(<<'PERL', 'nested_die');
my $x = 1;
print "before\n";
if ($x) { if ($x) { die "boom\n" } }
print "after\n";
PERL
    is count_op($json, 'If'), 2, 'both guards survive around the die';
    is count_op($json, 'Unwind'), 1, 'the die becomes an Unwind';
};

# REGRESSION GUARD, both directions. A rebind-only body must NOT be pushed onto
# the control-flow path -- it keeps the cheaper value merge. Without this a
# "fix" that simply made every arm build control flow would pass every test
# above while regressing the common case.
subtest 'a rebind-only nested body keeps the value merge' => sub {
    my $json = graph_for(<<'PERL', 'nested_rebind');
my $x = 1; my $n = 0;
if ($x) { if ($x) { $n = 7 } }
print "n=$n\n";
PERL
    is count_op($json, 'If'), 0,
        'no control flow built for a pure rebind body';
    ok count_op($json, 'TernaryExpr') >= 1, 'it merges as values instead';
};

done_testing;
