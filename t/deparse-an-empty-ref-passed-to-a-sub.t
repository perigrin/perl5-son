# ABOUTME: An empty `{}` or `[]` stored into a lexical that is passed to a sub round trips:
# ABOUTME: the callee's writes through the reference are seen by the caller.
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

my @cases = (
    [ q{sub f { my ($h)=@_; $h->{p}=2; return 1 } my $h={}; f($h); print keys %$h, "\n";},
      'a store through a hash reference parameter' ],
    [ q{sub f { my $h=shift; $h->{p}=2; return 1 } my $h={}; f($h); print keys %$h, "\n";},
      'the parameter taken by shift' ],
    [ q{sub f { my ($h)=@_; $h->{p}=2; return 1 } my $h={}; f($h); print $h->{p}, "\n";},
      'the caller reads the element back' ],
    [ q{sub f { my ($a)=@_; $a->[0]=2; return 1 } my $a=[]; f($a); print @$a, "\n";},
      'a store through an array reference parameter' ],
    [ q{sub f { $_[0]{p}=2; 1 } my $h; $h={}; f($h); print keys %$h, "\n";},
      'a plain assignment of {} to a declared lexical' ],
    [ q{sub f { my ($a)=@_; push @$a, 3; 1 } for my $i (1,2) { my $a=[]; f($a); print scalar(@$a), "\n" }},
      'a fresh [] each pass of a loop' ],
    [ q{sub f { $_[0]{q}=1 } sub g { my $h={}; f($h); return join ",", keys %$h } print g(), "\n";},
      'inside a sub' ],
    [ q{sub f {1} my $h={}; f($h); print ref($h), "\n";},
      'the reference survives a call that ignores it' ],
    [ q{sub f { 1 } my $h={}; f($h); undef $h; print defined($h)?1:0, "\n";},
      q{`undef $h` after the call clears the stored slot} ],
    [ q{sub f { 1 } my $h={a=>1}; f($h); undef $h; print defined($h)?1:0, "\n";},
      q{`undef $h` clears a non-empty reference too} ],
    [ q{sub f { $_[0]{p}=2 } my $h={}; f($h); undef $h; print defined($h)?1:0, "\n";},
      q{`undef $h` after the callee writes through it} ],
);

for my $c (@cases) {
    round_trips(@$c);
    emits_quietly(@$c);
}

done_testing;
