# ABOUTME: SoN::FromOptree->translate holds the code it translated: the package-write scan
# ABOUTME: remembers a CV by its address, and a freed CV's address is another CV's later.
use v5.42.0;
use Test2::V0;
use Scalar::Util qw(weaken);

use SoN;
use SoN::FromOptree;

# Found as a flake of t/from-optree-match-subject.t (about 3 runs in 100, at
# the base too): _scan_cv_package_writes skips a CV whose address it has
# read. In-process, each subtest's anon sub was freed after translate, and a
# later one allocated at the same address was taken as read: its `our $ps =
# "abc"` unseen, the package scalar was taken for unwritten and the match
# read the Constant -- a carried package scalar (W1). Held, an address names
# one CV for the process, as it does under -MO=SoN.
my $code = eval 'sub { our $kept = 1; $kept }' or die $@;
my $weak = $code;
weaken($weak);
SoN::FromOptree->translate($code);
undef $code;
ok defined $weak, 'the translated code is still alive';

done_testing;
