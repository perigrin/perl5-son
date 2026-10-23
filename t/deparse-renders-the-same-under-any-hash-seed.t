# ABOUTME: A render does not depend on perl's hash order: the same graph, rendered
# ABOUTME: under different PERL_HASH_SEEDs, gives byte-identical Perl.

use v5.42.0;
use Test2::V0;
use FindBin;
use Digest::MD5 qw(md5_hex);

# THE ARM WALK SHARED ONE VISITED SET ACROSS EVERY `if`, taken in hash order.
# Walked first, an inner `if` marked its arm; the enclosing `if`'s walk then
# stopped there and never reached what follows the inner join, so a use there
# counted as outside the arm or in it depending on the seed. A stale read was
# bound early under one seed and not another, and gate 3 measured 476 or 482
# from one run to the next (chalk's Bootstrap::Semiring::Precedence, whose
# B::SoN graph is the fixture: the order depends on every hash used before the
# walk, so a small program does not reproduce it).
my $fixture = "$FindBin::Bin/data/chalk-precedence.son.json.gz";
my %renders;
for my $seed (1 .. 6) {
    my $out = qx(PERL_HASH_SEED=$seed $^X -I$FindBin::Bin/../lib -MSoN::Deparse -MJSON::PP -MIO::Uncompress::Gunzip=gunzip -e 'gunzip(\$ARGV[0] => \\my \$j) or die; print SoN::Deparse->new->render(decode_json(\$j)) // "REFUSED"' $fixture);
    $renders{ md5_hex($out) }++;
}
is scalar(keys %renders), 1, 'six seeds, one render' or diag join ' ', %renders;

done_testing;
