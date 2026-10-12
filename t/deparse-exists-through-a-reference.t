# ABOUTME: exists and delete through a scalar holding a reference: the element op says hash
# ABOUTME: or array, which the container cannot, and the emission must index the same way.

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



# THE CONTAINER CANNOT SAY WHICH. `exists $h->{a}` over a scalar holding a
# reference had nothing to tell hash from array, and rendered
# `exists($h->[...])`: "Not an ARRAY reference". The op says -- the element
# under exists/delete is a helem or an aelem -- and the node carries it now,
# as a Subscript does.
subtest 'exists and delete through a reference' => sub {
    round_trips(q{sub f { my ($h)=@_; if (exists $h->{a}) { print "y\n" } } f({a=>1});},
        'exists $h->{a}');
    round_trips(q{sub f { my ($h)=@_; for my $key (qw(a b)) { print exists $h->{$key} ? "y" : "n" } print "\n" } f({a=>1});},
        'exists $h->{$key}, in a loop');
    round_trips(q{sub f { my ($k,$h)=@_; for my $key (sort keys %$h) { if (exists $h->{$key}) { return $key if $h->{$key} > $k } } return "none" } print f(1, {a=>1,b=>2,c=>3}), " ", f(9, {a=>1}), "\n";},
        'exists in an arm, return in the arm, in a loop');
    round_trips(q{sub f { my ($r)=@_; print exists $r->[1] ? "y" : "n", exists $r->[5] ? "y" : "n", "\n" } f([1,2]);},
        'exists $r->[i]');
    round_trips(q{sub f { my ($h)=@_; my $v = delete $h->{a}; print $v, " ", join(",", sort keys %$h), "\n" } f({a=>1,b=>2});},
        'delete $h->{a}');
    round_trips(q{sub f { my ($r)=@_; my $v = delete $r->[1]; print $v, " ", scalar(@$r), "\n" } f([1,2]);},
        'delete $r->[i]');
    round_trips(q{sub f { my ($h)=@_; delete $h->{a}; print join(",", sort keys %$h), "\n" } f({a=>1,b=>2});},
        'a void delete $h->{a}');
    round_trips(q{sub f { my ($h,$k)=@_; for my $i (1..3) { delete $h->{$i} if $i > $k } print join(",", sort keys %$h), "\n" } f({1=>1,2=>2,3=>3}, 1);},
        'a guarded void delete, in a loop');
};

done_testing;
