# ABOUTME: A `use Module LIST` / `no Module LIST` is emitted as the statement it was, not as
# ABOUTME: the BEGIN block perl lowers it to -- chalk reads lib/ source and looks for the `use`.

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

sub round_trips ($src, $name, $spelled = undef) {
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
    like $out, $spelled, "$name: spelled as a statement" if $spelled;
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# perl LOWERS `use X LIST` to `BEGIN { require X; X->import(LIST) }`, and the
# emission spelled that: `BEGIN { require("utf8.pm"); "utf8"->import() }`.
# Same program -- and chalk's perl-actions tests read lib/Chalk/IR/Node/
# Start.pm and look for its `use utf8` and `use experimental` statements.
round_trips(<<'SRC', 'use utf8', qr/^use utf8;$/m);
use utf8; my $s = "abc"; print length($s), "\n";
SRC

round_trips(<<'SRC', 'use with a constant list', qr/^use List::Util "sum", "max";$/m);
use List::Util qw(sum max); print sum(1, 2, 3), max(4, 5), "\n";
SRC

round_trips(<<'SRC', 'no with a constant list', qr/^no warnings "once";$/m);
no warnings 'once'; $main::x = 1; print "ok\n";
SRC

round_trips(<<'SRC', 'use with an empty list', qr/^use List::Util \(\);$/m);
use List::Util (); print List::Util::sum(1, 2), "\n";
SRC

round_trips(<<'SRC', 'use experimental in a class', qr/^use experimental "class";$/m);
use v5.42; use experimental 'class';
class C { method m { return 7 } } print C->new->m, "\n";
SRC

# `use experimental 'class'` TURNS ON THE FEATURE AND SILENCES ITS WARNING,
# so the class section's own two lines repeated it -- and chalk counts them:
# perl-actions-tier-a found its class one statement later than the source
# put it.
{
    my $src = "use v5.42; use experimental 'class';\nclass C { method m { 7 } }\nprint C->new->m, \"\\n\";\n";
    my $out = SoN::Deparse->new->render(graph_of($src));
    unlike $out, qr/^use feature 'class';$/m,
        'the class feature is not said twice after use experimental';
    is run_perl($out), "7\n", '... and the class still compiles';
}
{
    my $src = "use v5.42; use feature 'class'; no warnings 'experimental::class';\nclass C { method m { 7 } }\nprint C->new->m, \"\\n\";\n";
    my $out = SoN::Deparse->new->render(graph_of($src));
    is run_perl($out), "7\n", 'a class under use feature still compiles';
}

# A PLAIN SUB DECLARED IN A CLASS BLOCK stays in it. Spelled outside as
# `sub Chalk::IR::Node::Start::identity_kind`, it is the same sub to perl but
# a top-level one to chalk, which reads the class's statements from source.
{
    my $src = "use v5.42; use experimental 'class';\nclass C { method m { 7 } sub kind { 'k' } }\nprint C->new->m, C::kind(), \"\\n\";\n";
    my $out = SoN::Deparse->new->render(graph_of($src));
    like $out, qr/^class C \{\n.*^sub kind \{.*^\}\nmy \$eff/ms, 'a sub declared in a class is emitted in it';
    unlike $out, qr/^sub C::kind\b/m, '... and not again outside it';
    is run_perl($out), "7k\n", '... and still runs';
}

done_testing;
