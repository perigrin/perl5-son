# ABOUTME: A field keeps the attributes the source gave it -- `:reader`, and `:param` with
# ABOUTME: no name when the name is the field's own -- rather than an accessor written out.

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

sub round_trips ($src, $name, $spelled = undef, $not = undef) {
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
    like $out, $spelled, "$name: spelled as the source" if $spelled;
    unlike $out, $not, "$name: not spelled otherwise" if $not;
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# A `:reader` WAS WRITTEN OUT AS THE METHOD IT SYNTHESIZES -- `method value {
# return $value }` -- the same object to perl, and chalk's
# perl-target-perl-tier-b.t, which reads lib/Chalk/IR/Node/Constant.pm as
# source, looks for the attribute.
round_trips(<<'SRC', 'a reader field', qr/^field \$a :param :reader;$/m, qr/^method a\b/m);
use v5.42; use experimental 'class';
class C { field $a :param :reader; field $c = 3; method c { $c } }
my $o = C->new(a => 1); print $o->a, $o->c, "\n";
SRC

round_trips(<<'SRC', 'a reader with a default', qr/^field \$t :param :reader = "string";$/m);
use v5.42; use experimental 'class';
class C { field $t :param :reader = 'string'; }
print C->new->t, C->new(t => "x")->t, "\n";
SRC

round_trips(<<'SRC', 'a param named apart from its field', qr/^field \$x :param\(ex\);$/m);
use v5.42; use experimental 'class';
class C { field $x :param(ex); method x { $x } }
print C->new(ex => 4)->x, "\n";
SRC

done_testing;
