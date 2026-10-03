# ABOUTME: A call whose last argument is a shift, pop or each keeps that argument: only a
# ABOUTME: memory input the producer marked is a memory edge, not every memory-carrying value.

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


# THE RENDERER TOOK A CALL'S LAST INPUT FOR ITS MEMORY EDGE whenever that
# input was a memory point -- and a `shift` result is one, since shift
# mutates its array. So `push @o, $n` with $n just shifted rendered
# `push(@o)`: the value vanished. chalk's IR::Analysis walks its worklists
# exactly so. The producer now marks the calls it appends memory to.
round_trips(<<'SRC', 'push of a value just shifted');
sub f { my @q = @_; my %s; my @o; while (@q) { my $n = shift @q; next if $s{$n}++; push @o, $n } return "@o" }
print f(1, 2, 2, 3), "\n";
SRC

round_trips(<<'SRC', 'push of a shift, directly');
sub f { my @q = @_; my @o; push @o, shift @q; push @o, shift @q; return "@o|@q" } print f(1, 2, 3), "\n";
SRC

round_trips(<<'SRC', 'a sub called with a pop last');
sub g { return join("-", @_) } sub f { my @q = @_; return g("x", pop @q) } print f(1, 2, 3), "\n";
SRC

round_trips(<<'SRC', 'push onto a declared-empty array from each');
my %h = (a => 1); my @o; push @o, each %h; print "@o\n";
SRC

# `each` IN LIST CONTEXT IS A PAIR, and the call carried no context, so its
# binding took a scalar -- the key alone. `my ($k, $v) = each %h` is the
# common shape.
round_trips(<<'SRC', 'each in list context');
my %h = (a => 1); my ($k, $v) = each %h; my @p = each %h; print "$k=$v ", scalar(@p), "\n";
SRC

done_testing;
