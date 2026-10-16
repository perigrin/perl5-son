# ABOUTME: A list assign from @_ into declared scalars binds each target to its
# ABOUTME: own element of @_, as perl does, rather than to @_ or to nothing.

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


# `($P) = @_` INTO A DECLARED SCALAR -- a package scalar or an earlier `my` --
# is not the padrange form, so nothing bound the targets: one target was
# stored the whole @_ (its count, 1 for "abc") and two were dropped.
round_trips(<<'S', 'one package scalar from @_');
our $P; sub f { ($P)=@_; return $P } print f("abc"), "\n";
S

round_trips(<<'S', 'two package scalars from @_');
our ($P,$Q); sub f { ($P,$Q)=@_; return $P.$Q } print f("abc","d"), "\n";
S

round_trips(<<'S', 'two declared lexicals from @_');
sub f { my ($x,$y); ($x,$y)=@_; return $x.$y } print f("abc","d"), "\n";
S

round_trips(<<'S', 'more targets than arguments take undef');
sub f { my ($x,$y); ($x,$y)=@_; return defined $y ? "def" : "undef" } print f("abc"), "\n";
S

round_trips(<<'S', 'a declared lexical from @_, then changed');
sub f { my $x; ($x)=@_; $x .= "z"; return $x } print f("abc"), "\n";
S

round_trips(<<'S', 'a package scalar substituted in an arm');
our $P; sub f { ($P)=@_; if (length($P) == 3) { $P =~ s/c$// } return $P } print f("abc"), f("abcc"), "\n";
S

done_testing;
