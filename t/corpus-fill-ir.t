# ABOUTME: tools/corpus-fill-ir.pl writes each corpus's graph block by that
# ABOUTME: corpus's convention, keeps every other block, and records refusals.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use YAML::PP;

my $root = tempdir(CLEANUP => 1);
mkdir "$root/pvm";
mkdir "$root/chalk";

sub write_file ($path, $text) {
    open my $fh, '>', $path or die $!; print $fh $text; close $fh;
}
sub slurp ($path) { local (@ARGV, $/) = ($path); <> }

write_file("$root/pvm/t.md", <<'MD');
# T

## prints

```perl
print "hi\n";
```

```output
hi
```

## does not parse

```perl
my $x = ;
```

```behavior
parses: no
```
MD

write_file("$root/chalk/t.md", <<'MD');
# T

## adds

```perl
# source
1 + 2
```

```behavior
return: 3
```

```ir
%add = Add(%c1, %c2) :Int
L: GREEN
```

## needs 5.42

```perl
# source
my $x = 0;
try { $x = 1 } catch ($e) { $x = 2 }
$x
```

## never compiles

```perl
# source
my $x = ;
```
MD

my $out = qx($^X tools/corpus-fill-ir.pl $root/pvm $root/chalk 2>&1);
is $? >> 8, 0, 'the fill runs' or diag $out;
like $out, qr/^cases: 4$/m, 'four cases: the parses:no one has no graph';

my $pvm = slurp("$root/pvm/t.md");
my @ir = $pvm =~ /^```ir\n(.*?)^```/msg;
is scalar(@ir), 1, 'pvm: one ir block, none for the case that does not parse';
like $ir[0], qr/^main::__PROGRAM__: \{start: 0/m, '... holding the program graph';
ok YAML::PP->new->load_string($ir[0]), '... as YAML';

my $chalk = slurp("$root/chalk/t.md");
like $chalk, qr/^```ir\n%add = Add\(%c1, %c2\) :Int\nL: GREEN\n```$/m,
    "chalk: its own hand-written ir block is untouched";
my @son = $chalk =~ /^```son\n(.*?)^```/msg;
is scalar(@son), 3, 'chalk: every case has a son block';
like $son[0], qr/^main::corpus_case: /m, '... the fragment is corpus_case';
unlike $son[1], qr/refused/, '... a 5.42 fragment (try/catch) compiles';
like $son[2], qr/^refused: \[\n  "does not compile: syntax error/m,
    '... and one that never compiles is recorded, not left empty';
ok YAML::PP->new->load_string($_), '... each block is YAML' for @son;

my $check = qx($^X tools/corpus-fill-ir.pl --check $root/pvm $root/chalk 2>&1);
like $check, qr/^drifted: 0$/m, 'a refill has nothing to change';

done_testing;
