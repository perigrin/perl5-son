# ABOUTME: A value `&&` / `||` / `//` in a loop body whose right side calls runs that call
# ABOUTME: only when the left side lets it -- a branch with a merged value, not a refusal.

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


# THE LOOP BODY'S VALUE short-circuit took only pure arms; an arm with a call
# fell to the loop-condition handler, which refused "nested and/or inside a
# loop body" -- 37 of chalk's graphs, `next unless $n->can(...) && ...` among
# them. The call is counted, so running it unconditionally would show.
round_trips(<<'SRC', 'a three-way && with calls guarding next');
my $n = 0; sub g { $n++; return $_[0] }
sub f { my $o = ""; for my $x (@_) { next unless g($x) && g($x) > 1 && g($x) < 9; $o .= $x } return "$o:$n" }
print f(1, 2, 3, 9), "\n";
SRC

round_trips(<<'SRC', 'a value && with a call, in a foreach');
my $n = 0; sub g { $n++; return $_[0] }
sub f { my $o = ""; for my $x (@_) { my $v = $x && g($x) && g($x) > 1; $o .= $v ? "y" : "n" } return "$o:$n" }
print f(0, 2, 1), "\n";
SRC

round_trips(<<'SRC', 'a value || with a call, in a while');
my $n = 0; sub g { $n++; return 7 }
sub f { my @q = @_; my $o = ""; while (@q) { my $x = shift @q; my $v = $x || g(); $o .= $v } return "$o:$n" }
print f(0, 2, 0), "\n";
SRC

round_trips(<<'SRC', 'a value // with a call, in a foreach');
my $n = 0; sub g { $n++; return 7 }
sub f { my $o = ""; for my $x (@_) { my $v = $x // g(); $o .= $v } return "$o:$n" }
print f(undef, 2, undef), "\n";
SRC

# THE BRANCH THIS BUILDS IS A DIAMOND INSIDE THE REST OF THE BODY, and the
# renderer took it for the body's merge: after a `next` guard it emitted the
# rest of the body, then resumed at the diamond's Region and emitted it again
# -- `my \$eff` declared twice, in chalk's Schedule::Elaborate.
round_trips(<<'SRC', 'two call guards, then an if');
package O { sub new { my ($c, %a) = @_; bless {%a}, $c } sub operation { $_[0]{op} } sub region { $_[0]{r} } sub id { $_[0]{id} } sub inputs { $_[0]{in} } }
sub vd { my ($n) = @_; return $n if defined $n && $n->operation eq 'V'; return undef }
sub el {
    my ($loop, $cs, $phis) = @_;
    for my $c (@$cs) {
        next unless defined $c && $c->can('operation');
        next unless $c->operation eq 'Phi';
        my $r = $c->region;
        next unless defined $r && $r->id eq $loop->id;
        my $v = vd($c->inputs->[0]);
        if (defined $v) {
            push @$phis, { incoming => [] };
        }
    }
    return scalar @$phis;
}
my $L = O->new(id => 'L');
my $V = O->new(op => 'V', id => 'v');
my @cs = (O->new(op => 'Phi', r => $L, in => [$V]), undef, O->new(op => 'X'), O->new(op => 'Phi', r => O->new(id => 'M'), in => [$V]), O->new(op => 'Phi', r => $L, in => [O->new(op => 'Y')]));
print el($L, \@cs, []), "\n";

SRC

done_testing;
