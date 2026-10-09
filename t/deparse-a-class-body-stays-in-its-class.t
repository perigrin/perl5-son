# ABOUTME: Statements written inside a class or package block are emitted there, where
# ABOUTME: they ran: `our %X = ...` stays unqualified, and file-level code before it runs first.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# A CLASS BODY'S OWN STATEMENTS were emitted after the class, at file level
# in package main, so `our %STATEMENT_EFFECT_OPS = ...` in chalk's
# NodeFactory came back as `%Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS =
# (...)` -- correct Perl, but chalk's grammar has no package-qualified
# aggregate, and perl-recognize-phase5.t rejected the emitted module. Emitted
# in their block, at the point the block stood, they spell the variable as
# the source did.
sub emitted ($src) {
    my $data = graph_of($src) or return;
    return SoN::Deparse->new->render($data);
}

round_trips(<<'SRC', 'our in a package block');
package P { our %X = map { $_ => 1 } qw(a b); sub has { exists $P::X{$_[0]} ? 1 : 0 } }
print P::has("a"), P::has("z"), "\n";
SRC

round_trips(<<'SRC', 'our in a class block');
use v5.42.0; use experimental 'class';
class C { our @NAMES = ("x", "y"); method count { scalar @C::NAMES } }
print C->new->count, "\n";
SRC

round_trips(<<'SRC', 'a class body reads file-level code that ran before it');
use v5.42.0; use experimental 'class';
my %D = (a => 1, b => 2);
class C { our $N = scalar keys %D; method n { $C::N } }
print C->new->n, "\n";
SRC

# THE STATEMENT FORM, `package P;` at the top of a file, as chalk's
# Transform::T2 is written: a constant table hoisted above the program's
# statements stayed outside the package's region, qualified.
my $stmt = emitted(<<'SRC') // '';
package P;
our %TABLE = (a => 1, b => 2);
sub has { exists $TABLE{$_[0]} ? 1 : 0 }
package main;
print P::has("a"), P::has("z"), "\n";
SRC
unlike $stmt, qr/%P::TABLE\b/, 'a package-statement table is not spelled qualified';
round_trips(<<'SRC', 'a table under a package statement');
package P;
our %TABLE = (a => 1, b => 2);
sub has { exists $TABLE{$_[0]} ? 1 : 0 }
package main;
print P::has("a"), P::has("z"), "\n";
SRC

my $out = emitted(<<'SRC') // '';
package P { our %X = map { $_ => 1 } qw(a b); sub has { exists $P::X{$_[0]} ? 1 : 0 } }
print P::has("a"), "\n";
SRC
like   $out, qr/\bour %X\b/,      'the package aggregate is declared our';
unlike $out, qr/%P::X\b/,          'and not spelled qualified';
unlike $out, qr/%(\S+) = %\1;/,    'with no self-assignment after it';

SKIP: {
    my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
    skip 'no chalk clone', 2 unless -d "$chalk/.git";
    # The module needs chalk's lib/ to compile; read it from the pinned
    # commit, never the working tree.
    my $tree = tempdir(CLEANUP => 1);
    system("git -C '$chalk' archive 5948f648 lib | tar -x -C '$tree'") == 0
        or skip 'cannot read chalk 5948f648', 2;
    my $j = qx($^X -Ilib -I$tree/lib -MO=-q,SoN,json $tree/lib/Chalk/IR/NodeFactory.pm 2>/dev/null);
    my $data = eval { JSON::PP->new->decode($j) };
    my $src = $data ? (SoN::Deparse->new->render($data) // '') : '';
    ok length($src), 'NodeFactory renders' or skip 'no emission', 1;
    unlike $src, qr/%Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS\b/,
        "chalk's NodeFactory declares its table in its class";
}

done_testing;
