# ABOUTME: The LLVM corpus census sorts each case into one bucket: it lowers through
# ABOUTME: chalk and lli prints perl's output, prints something else, or is a named gap.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use FindBin;

my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
skip_all "no chalk clone at $chalk (set SON_CHALK)" unless -d "$chalk/.git";
skip_all 'no lli on PATH' unless grep { -x "$_/lli" } split /:/, $ENV{PATH};

# THREE CASES, ONE PER OUTCOME the census must tell apart: one chalk lowers
# and lli runs to perl's output; the same program recorded with the wrong
# output, which lli's right answer must not match; and one chalk refuses with
# a named GAP (a string-compared sort over an aggregate, at the pin).
my $dir = tempdir(CLEANUP => 1);
open my $fh, '>', "$dir/cases.md" or die $!;
print $fh <<'MD';
## adds

```perl
my $x = 1 + 2; print "x=$x\n";
```

```output
x=3
```

## adds, recorded wrong

```perl
my $x = 1 + 2; print "x=$x\n";
```

```output
x=4
```

## sorts keys

```perl
my %h = (a=>1,b=>2); for my $k (sort keys %h) { print "$k=$h{$k}\n" }
```

```output
a=1
b=2
```
MD
close $fh;

my $out = qx(SON_CORPUS=$dir SON_CHALK=$chalk $^X $FindBin::Bin/../tools/corpus-llvm-roundtrip.pl -v 2>&1);
my %n;
$n{$1} = $2 while $out =~ /^(\w+)\s+(\d+)$/mg;

like $out, qr/^cases: 3$/m, 'it reads the three cases';
is $n{ROUNDTRIP}, 1, 'the program lli runs to perl\'s output round-trips' or diag $out;
is $n{DIFFERS},   1, 'the one recorded wrong differs' or diag $out;
is $n{GAP},       1, 'the one chalk will not lower is a gap' or diag $out;
like $out, qr/^GAP_CAUSE\s+1\s+sort with a STRING comparator/m,
    'the gap is ranked by its cause';
unlike $out, qr/^(?:GAP|LOAD)_CAUSE.* at \S+ line \d/m, 'a cause carries no source location';
like $out, qr/^STATUS 003 GAP\s+cases\.md: .*sort with a STRING comparator/m,
    '-v names each case\'s outcome';

# A CAUSE IS KEYED ON ITS CONSTRUCT: names in quotes and numbers vary per
# case, and the same missing feature must count once.
{
    use lib "$FindBin::Bin/../tools/lib";
    require CorpusLlvmCause;
    is CorpusLlvmCause::cause_key(q{LLVM backend: cannot lower op=BitAnd (not in literal-arithmetic slice) at /tmp/x/Context.pm line 12, <> line 1.}),
        'cannot lower op=BitAnd', 'a backend refusal keeps its op';
    is CorpusLlvmCause::cause_key(q{direct call to 'main::f': callee has effect(s) on its control chain (print/store/...) that inlining does not yet thread in program order.}),
        'direct call to X: callee has effect(s) on its control chain', 'a callee name is not part of the cause';
    is CorpusLlvmCause::cause_key(q{from_json failed: Unknown data node operation: Exists at /tmp/x/NodeFactory.pm line 9, <> line 1.}),
        'Unknown data node operation: Exists', 'a load failure names the node it did not know';
    is CorpusLlvmCause::cause_key("direct call to 'main::f': callee reads 0 positional argument(s) via `shift \@_` but the call passes 2 \xe2\x80\x94 arity mismatch"),
        'direct call to X: callee reads N positional argument(s) via `shift @_` but the call passes N',
        'an em dash in UTF-8 bytes ends the key, and counts are not part of it';
}

done_testing;
