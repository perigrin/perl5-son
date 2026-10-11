# ABOUTME: `$pkg =~ s///` inside a list -- call arguments, print -- yields only its count:
# ABOUTME: the package target its stacked gvsv pushed is not left riding in the list.

use v5.42.0;
use Test2::V0;
use JSON::PP;
# ABOUTME: A whole-aggregate assignment in a branch arm, in a loop or straight-line, round
# ABOUTME: trips: each assigned version is its own variable and an array merge stays an array.

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


round_trips('our $w = "ab"; sub ok { print scalar(@_), " @_\n" } ok(1, $w =~ s/a//); print "$w\n";',
    'a package subst as a call argument');
round_trips('our $w = "ab"; print 1, $w =~ s/a//, "\n"; print "$w\n";',
    'a package subst in a print list');
round_trips('our $warn = "ab\n"; sub ok ($$) { print $_[1] ? "ok " : "not ok ", $_[0], "\n" } ok 1, ($warn =~ s/a[^\n]+\n//s); print length($warn), "\n";',
    'perl comp/redef.t: a prototyped ok over a package subst');
round_trips('our $g = "aaa"; $g =~ s/a/b/; $g =~ s/b/c/; print "$g\n";',
    'two package substs in void context');
round_trips('my $w = "ab"; sub ok { print scalar(@_), " @_\n" } ok(1, $w =~ s/a//);',
    'a lexical subst as a call argument');


# A RE-WALK DOES NOT INHERIT THE SUBST THE FIRST WALK BOUND: the later
# `$warn eq ""` read is bound after the call, which re-walks the chain.
round_trips(q{our $warn; BEGIN { $warn = "ab\n" } sub ok ($$) { print $_[1] ? "ok " : "not ok ", $_[0], "\n" } ok 1, $warn =~ s/a[^\n]+\n//s; ok 2, $warn eq "";},
    q{a package subst in a call, then the variable read, in a re-walked chain});

done_testing;
