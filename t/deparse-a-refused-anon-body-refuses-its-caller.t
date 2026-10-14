# ABOUTME: A lifted body the producer refused is absent from the graph, so a caller
# ABOUTME: that names it refuses to render rather than emitting a call into nothing.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
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

# The body is refused for $body_cause, and the whole program refuses for
# $render_cause. Before the guard, the second half was an emitted program
# that died "Undefined subroutine" -- a render that looked successful.
sub caller_refuses ($src, $body_cause, $render_cause, $name) {
    my $data = graph_of($src);
    like producer_stderr(), $body_cause, "$name: the body is refused, naming its cause";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    ok !defined $out, "$name: the program does not render"
        or diag "--- emitted ---\n$out--- runs as ---\n" . run_perl($out);
    like $d->gap // '', $render_cause, "$name: the refusal names the missing body";
}

my $ctx  = qr/GAP: a \/g match in the caller's context/;
my $last = qr/GAP: a store to an array's last index/;
my $anon = qr/GAP: an? (?:anonymous sub|call to) `[^`]*__ANON__:\d+:\d+`, which is not in the graph/;
my $call = qr/GAP: a call to `[^`]*`, which is not in the graph/;

caller_refuses(q{my $f = sub { my $s = shift; $s =~ /\d/g }; my $x = $f->("a1"); print "$x\n";},
    $ctx, $anon, 'an anon sub held in a lexical');
caller_refuses(q{my $x = sub { my $s = shift; $s =~ /\d/g }->("a1"); print "$x\n";},
    $ctx, $anon, 'an anon sub called where it is written');
caller_refuses(q{my $f = sub { my $g = sub { my $s = shift; $s =~ /\d/g }; $g->(shift) }; my $x = $f->("a1"); print "$x\n";},
    $ctx, $anon, 'an anon sub nested in an anon sub');
caller_refuses(q{my @r = sort { my $f = sub { $_[0] =~ /\d/g }; $f->("a$a") <=> 0 or $a <=> $b } 3,1,2; print "@r\n";},
    $ctx, $anon, 'an anon sub in a sort comparator block');
caller_refuses(q{my @r = map { my $f = sub { $_[0] =~ /\d/g }; scalar $f->($_) } "a1","b"; print "@r\n";},
    $ctx, $anon, 'an anon sub in a map block');
caller_refuses(q{sub g { my $s = shift; $s =~ /\d/g } my $x = g("a1"); print "$x\n";},
    $ctx, $call, 'a named sub');
caller_refuses(q{sub byg { "$a" =~ /3/g } my @r = sort byg 3,1,2; print "@r\n";},
    $ctx, qr/GAP: a sort comparator `main::byg`, which is not in the graph/, 'a named sort comparator');

# ANY REFUSAL, not only the /g one: an anon body refused for an unrelated
# cause left the same dangling call.
caller_refuses(q{my $f = sub { my @a = (1,2); $#a = 0; scalar @a }; print $f->(), "\n";},
    $last, $anon, 'an anon sub refused for another cause');
caller_refuses(q{my %h = (k => sub { my @a = (1,2); $#a = 0; scalar @a }); print $h{k}->(), "\n";},
    $last, $anon, 'an anon sub stored in a hash');

# A METHOD IS RESOLVED AT RUNTIME, through @ISA, and the Call carries only the
# invocant's class -- so the renderer cannot tell a refused method from an
# inherited one, and still emits a call that dies.
{
    my $data = graph_of(q{package P; sub m1 { my ($c, $s) = @_; $s =~ /\d/g } package main; my $x = P->m1("a1"); print "$x\n";});
    like producer_stderr(), $ctx, 'a method: the body is refused, naming its cause';
    my $d = SoN::Deparse->new;
    todo 'a method call does not record which sub it resolves to' => sub {
        ok !defined $d->render($data), 'a method: the program does not render';
    };
}

done_testing;
