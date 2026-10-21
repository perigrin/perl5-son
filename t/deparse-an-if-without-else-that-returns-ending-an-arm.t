# ABOUTME: An if without else ending an arm is a short-circuit whose arm returns:
# ABOUTME: the return is an exit, and the path that skipped it goes on alone.

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

# PERL COMPILES `if (C) { BODY }` WITHOUT AN ELSE AS `C and BODY`. Ending
# an arm that ends a sub, it takes the caller's context, and a BODY that
# returns made a short-circuit whose arm is no value: refused, in a value
# arm and in an arm that stores (chalk's LLVM::Context
# _update_var_table_for_phi). The return is the arm's exit; the path that
# skipped it carries the condition's value, as perl's does.
round_trips(q{sub f { my ($i, $vd) = @_; if ($i eq "P") { if (defined $vd && $vd eq "V") { return 1 } } } print f("P","V"), "|", scalar(f("P", undef)) // "u", "|", scalar(f("Q","V")), "\n";},
    'a nested if that returns, ending a sub');
round_trips(q{sub f { my ($s, $i, $vd) = @_; if ($i eq "P") { if (defined $vd && $vd eq "V") { $s->{t} = $vd; return 1 } } } my $s = {}; my @r = (f($s, "P", "V"), scalar(f($s, "P", undef)) // "u", scalar(f($s, "Q", "V"))); print "@r|$s->{t}\n";},
    'a nested if that stores and returns, ending a sub');
round_trips(q{package N { sub new { bless { o => $_[1], i => $_[2], id => $_[3] }, $_[0] } sub operation { $_[0]{o} } sub inputs { $_[0]{i} } sub id { $_[0]{id} } }
sub upd { my ($self, $phi, $ref) = @_; my $inputs = $phi->inputs; return unless defined $inputs && @$inputs; my $init = $inputs->[0]; return unless defined $init;
  if ($init->operation eq 'PadAccess') { my $vd = $init->inputs->[0]; if (defined $vd && $vd->operation eq 'VarDecl') { $self->{t}{ $vd->id } = $ref; $self->{p}{ $phi->id } = $vd->id; return } } }
my $s = {}; upd($s, N->new("Phi", [N->new("PadAccess", [N->new("VarDecl", [], 5)])], 9), "R"); upd($s, N->new("Phi", [N->new("PadAccess", [undef])], 3), "Q"); upd($s, N->new("Phi", [], 4), "Z");
print join(",", map { "$_=$s->{t}{$_}" } sort keys %{$s->{t}}), " ", join(",", %{$s->{p}}), "\n";},
    'chalk\'s phi var-table update');

# NOT UNDER AN if/else: in its caller's context the if/else's merge is the
# renderer's open hole, and with the arm's exit recorded the else arm and
# the merge were dropped -- `9 3 3 3` for perl's `9 0  5`. It refuses.
round_trips(q{my %t; sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { $t{$b} = $a; return 9 } } } my @r = (scalar(f(1, "P", 3)), scalar(f(1, "P", 0)), scalar(f(1, "", 4)), scalar(f(0, 1, 1))); my @l = f(1, "Q", 0); print "@r|", scalar(@l), "[@l]|", join(",", map {"$_=$t{$_}"} sort keys %t), "\n";},
    'a store-and-return arm in an if with no else, in each context');
{
    my $data = graph_of(q{my %t; sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { $t{$b} = $a; return 9 } } else { 5 } } print scalar(f(1, "P", 0)), "\n";});
    like producer_stderr(), qr/GAP: a short-circuit whose arm is not a single value/,
        'a store-and-return arm under an if/else in the caller\'s context refuses';
}

done_testing;
