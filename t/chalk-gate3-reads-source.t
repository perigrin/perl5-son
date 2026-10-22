# ABOUTME: Which chalk test files read lib/ as source, and so are deferred from
# ABOUTME: gate 3: a path quoted, listed in qw(), or built on the repo root.

use v5.42.0;
use Test2::V0;
use FindBin;
use lib "$FindBin::Bin/../tools/lib";
use ChalkGate3 qw(reads_source_text);

ok reads_source_text(q{open my $fh, '<', 'lib/Chalk/IR/Graph.pm'}), 'a quoted module path';
ok reads_source_text(q{find(sub { ... }, 'lib/Chalk/')}), 'a quoted lib/Chalk directory';
ok reads_source_text(q{use File::Find;}), 'a walk';
ok reads_source_text(q{my @f = glob("$root/lib/**/*.pm");}), 'a glob over lib';

# A PATH IN A qw() LIST is read the same way: these two opened Context.pm and
# grepped its text, and against the overlay they measured the emitted text
# (chalk's llvm-method-abi-refinement.t, llvm-repr-machine-type-seam.t).
ok reads_source_text(q{for my $f (qw(lib/Chalk/Target/LLVM.pm lib/Chalk/Target/LLVM/Context.pm)) {}}),
    'module paths in a qw() list';
ok reads_source_text("for my \$p (qw(\n    lib/Chalk/IR/Analysis.pm\n)) {}"),
    'one per line in a qw() list';
ok reads_source_text(q{my $target_file = "$repo_root/lib/Chalk/Bootstrap/Semiring/Boolean.pm";}),
    'a path built on the repo root';

ok !reads_source_text(q{open my $fh, '<', 't/lib/Chalk/CodeGen/Harness.pm'}), 'a test helper under t/lib is not lib/';
ok !reads_source_text(q{[ 't/lib/Chalk/CodeGen/Harness/HarvestPin.pm' ],}), 'nor in a list';
ok !reads_source_text("# Site: lib/Chalk/Bootstrap/IR/Optimizer.pm:10\nuse Chalk::IR;"), 'a path in a comment';
ok !reads_source_text(q{use Chalk::Bootstrap::Earley; my $p = Chalk::Bootstrap::Earley->new;}), 'a module used, not read';

done_testing;
