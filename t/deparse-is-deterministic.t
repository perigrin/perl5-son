# ABOUTME: The deparser renders one wire to one text, whatever perl's hash seed: every
# ABOUTME: walk over a graph's nodes runs in id order, not in hash order.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

# Render the same JSON wire under several PERL_HASH_SEEDs, each in its own
# process, and collect the distinct outputs.
sub renderings ($json_file) {
    my %seen;
    for my $seed (1 .. 12) {
        my $out = qx(PERL_HASH_SEED=$seed $^X -Ilib -MJSON::PP -MSoN::Deparse -e 'local \$/; my \$d = SoN::Deparse->new; my \$o = eval { \$d->render(JSON::PP->new->utf8->decode(<STDIN>)) }; print defined \$o ? \$o : "GAP: " . (\$d->gap // \$\@)' < $json_file);
        $seen{$out}++;
    }
    return \%seen;
}

sub wire_of ($src_file, @inc) {
    my $json = "$dir/w." . int(rand 1e9) . ".json";
    my $inc = join ' ', map { "-I$_" } @inc;
    system("PERL_HASH_SEED=1 $^X -Ilib $inc -MO=-q,SoN,json,not_package=SoN $src_file > $json 2>/dev/null");
    return $json;
}

# THE MEASURED CASE. chalk's IR/Transform/T2.pm rendered at seeds 1-7 and
# refused at seed 8 ("a Phi whose region is a `Region` rather than a Loop"),
# with the producer's JSON byte-identical across seeds -- the renderer alone
# was order-dependent, through 33 walks over `values %$nodes`. It is read
# from the pinned chalk commit the census uses, so it needs a chalk clone.
SKIP: {
    my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
    my $snap = "$dir/chalk";
    mkdir $snap;
    skip "no chalk clone with 5948f648 at $chalk (set SON_CHALK)", 1
        unless system("git -C '$chalk' archive 5948f648 lib 2>/dev/null | tar -x -C '$snap' 2>/dev/null") == 0
            && -f "$snap/lib/Chalk/IR/Transform/T2.pm";
    my $json = wire_of("$snap/lib/Chalk/IR/Transform/T2.pm", "$snap/lib");
    my $r = renderings($json);
    is scalar(keys %$r), 1, 'chalk T2 renders to one text under 12 hash seeds'
        or diag join "\n---\n", map { substr($_, 0, 200) } keys %$r;
}

# AN IN-REPO PROGRAM with loops, branches and a class, so the guard has a
# subject without a chalk clone.
{
    my $src = "$dir/p.pl";
    open my $fh, '>', $src or die $!;
    print $fh <<'SRC';
use feature 'class'; no warnings 'experimental::class';
class Acc { field %seen; field $n = 0;
  method add($k) { return $seen{$k} if exists $seen{$k}; my $id = $n++; $seen{$k} = $id; return $id } }
my $a = Acc->new; my @ids;
for my $w (qw(x y x z)) { push @ids, $a->add($w) if length $w }
my %h = map { $_ => 1 } @ids;
print join(",", @ids), " ", join("", sort keys %h), "\n";
SRC
    close $fh;
    my $r = renderings(wire_of($src));
    is scalar(keys %$r), 1, 'an in-repo program renders to one text under 12 hash seeds'
        or diag join "\n---\n", map { substr($_, 0, 200) } keys %$r;
}

done_testing;
