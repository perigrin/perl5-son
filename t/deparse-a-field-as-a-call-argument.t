# ABOUTME: A class field passed straight to a sub is the field, not a fresh lexical:
# ABOUTME: the call-argument alias demotion must leave a field to its FieldAccess.

use v5.42.0;
use Test2::V0;
use JSON::PP;
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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


# A call argument is an alias, so the producer demotes its slot to memory --
# and a demoted FIELD rendered as `my $z;` inside the method, hiding the field.
round_trips('use v5.36; use experimental "class"; class C { field $z = 3; method m { foo($z) } sub foo { $_[0]+1 } } print C->new->m, "\n";',
    'a field passed to a package sub');
round_trips('use v5.36; use experimental "class"; class C { field $z = 3; sub ok2 ($v) { $v + 1 } method m { ok2($z) } } print C->new->m, "\n";',
    'a field passed to a signatured sub');
round_trips('use v5.36; use experimental "class"; class C { field $z = 3; sub bump { $_[0]++ } method m { bump($z); $z } } print C->new->m, "\n";',
    'a callee writes the field through $_[0]');

# The chalk shape: a class-block lexical predicate, a `my sub` over it, and a
# method that hands the `my sub` a field.
round_trips('use v5.36; use experimental "class"; class C { field $z = 3; my $p = sub ($n) { $n > 2 }; my sub ok ($v) { $p->($v) ? 1 : 0 } method m { ok($z) } } print C->new->m, "\n";',
    'a lexical sub over a class-block anon sub, given a field');
round_trips('use v5.36; use experimental "class"; class C { field $z = 3; my $k = 1; my sub ok ($v) { $v + $k } method m { ok($z) } } print C->new->m, "\n";',
    'a lexical sub over a class-block scalar, given a field');
round_trips('use v5.36; use experimental "class"; class C { field $z = 3; my $k = 1; my sub ok ($a, $b) { $a + $b + $k } method m { ok($z, $z) } } print C->new->m, "\n";',
    'a field passed twice');
round_trips('use v5.36; use experimental "class"; class C { field $z = 3; my $k = 1; my sub ok ($v) { $v + $k } method m { $z = ok($z); ok($z) } } print C->new->m, "\n";',
    'a field stored from the call, then passed again');
round_trips('use v5.36; use experimental "class"; class C { field $z :param = 3; my $p = sub ($n) { $n > 2 }; my sub ok ($v) { $p->($v) ? "y" : "n" } method m { ok($z) . ok(1) } } print C->new(z => 5)->m, "\n";',
    'a :param field passed to a lexical sub');

done_testing;
