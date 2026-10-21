# ABOUTME: A do block's value is its last statement's: an earlier statement's
# ABOUTME: leftover on the stack (`my $i = 0`) is no part of it.

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

# THE MAIN WALK KEPT AN EARLIER STATEMENT'S VALUE: `my %I = do { my $i = 0;
# map { $_->{name} => $i++ } @F }` built `(0, ...)`, every key shifted by one
# (chalk's LLVM::Context `%_STR_IDX`, `%_SLOT_IDX`).
round_trips(q{my @F = ({name => "a"}, {name => "b"}); my %I = do { my $i = 0; map { $_->{name} => $i++ } @F }; print join(",", map { "$_=$I{$_}" } sort keys %I), "\n";},
    'a do block of a counter and a map, at file scope');
round_trips(q{sub f { my @F = @_; my %I = do { my $i = 0; map { $_->{name} => $i++ } @F }; join(",", map { "$_=$I{$_}" } sort keys %I) } print f({name => "a"}, {name => "b"}), "\n";},
    'the same in a sub');

# AN ELEMENT IS NEVER AN ARRAY: read after `@F = (...)`, a shared array's
# element took that whole store's Array stamp, and `$_->{name}` was spelled as
# a list subscript (chalk's LLVM::Context `%_STR_IDX`).
round_trips(q{my @F = ({name => "a"}, {name => "b"}); sub ff { return @F } my %I = do { my $i = 0; map { $_->{name} => $i++ } @F }; sub ix { $I{$_[0]} } print ix("a"), ix("b"), scalar(ff()), "\n";},
    'a map over a shared array, read through each element');

done_testing;
