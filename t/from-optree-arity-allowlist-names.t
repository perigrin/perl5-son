# ABOUTME: Every name in the map/grep contribution allow-list must name a real
# ABOUTME: node class -- in an allow-list a typo silently drops a valid op.

use v5.42.0;
use Test2::V0;
use File::Spec;

# WHY THIS TEST EXISTS. The map/grep walk accepts a body contribution only when
# its node kind is KNOWN to yield exactly one value, and refuses anything else.
# That direction is deliberate: an unfamiliar shape becomes a GAP rather than a
# wrong count.
#
# But an allow-list has an asymmetric failure mode a deny-list does not. A name
# that matches no node kind is not merely dead weight -- it means the op it was
# meant to name is ABSENT from the set, so a body that is genuinely fine gets
# refused. The first draft of that list was written from memory and contained
# twenty such names (Chr, Ord, Sprintf, Join, Ternary...); `Ternary` matching
# nothing is why the real `TernaryExpr` was missing and comp/retainedlines.t
# over-refused.
#
# The node REGISTRY in NodeFactory is protected from this by construction: it
# maps a name to "SoN::IR::Node::$_", so a wrong name fails at class load. The
# allow-list has no such property -- it is a bare set of strings keyed on the
# same names -- so the protection has to be a test.

my $factory_dir = File::Spec->catdir(qw(lib SoN IR Node));
opendir my $dh, $factory_dir or die "opendir $factory_dir: $!";
my %class_exists = map { s/\.pm\z//r => 1 } grep { /\.pm\z/ } readdir $dh;
closedir $dh;
ok scalar(keys %class_exists), 'found the node class files' or done_testing, exit;

my $src = do {
    open my $fh, '<', File::Spec->catfile(qw(lib SoN FromOptree.pm))
        or die "open FromOptree.pm: $!";
    local $/;
    <$fh>;
};

my ($block) = $src =~ /YIELDS_ONE_VALUE \s* = \s* \{ .*? qw\( (.*?) \) \s* \}/xs;
ok defined $block, 'found the YIELDS_ONE_VALUE allow-list' or done_testing, exit;

my @names = grep { length } split /\s+/, $block;
ok scalar(@names) > 10, 'the allow-list is non-trivial (' . scalar(@names) . ' names)';

my @phantom = grep { !$class_exists{$_} } @names;
is \@phantom, [],
    'every allow-list name is a real node class (a phantom silently omits an op)';

done_testing;
