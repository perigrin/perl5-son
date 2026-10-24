# ABOUTME: A method call on a package (blessed-hash OO, not `class`) is typed by the
# ABOUTME: package's sub of that name, as a direct call is typed by its callee.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub stamps_of ($data, $graph, $op) {
    return [ map { $_->{stamp} } grep { $_->{op} eq $op } $data->{methods}{$graph}{nodes}->@* ];
}

# A PACKAGE'S METHOD IS ITS SUB. `O->m(5)` names class O, which declares no
# `method m` -- its `m` is a sub, recorded in the class's `subs`. Only
# method_return_types was consulted, so the call shipped Unknown, and the
# Add over two of them did too: chalk could not lower an Unknown sum.
my $src = <<'SRC';
package O { sub m { $_[1] * 2 } }
print O->m(5) + O->m(6), "\n";
SRC

my $data = graph_of($src);
is stamps_of($data, 'main::__PROGRAM__', 'Call'), [ 'Num', 'Num' ], 'each call is its sub\'s Num';
is stamps_of($data, 'main::__PROGRAM__', 'Add'), [ 'Num' ], 'and so is their sum';

my $d = SoN::Deparse->new;
my $out = $d->render($data);
is run_perl($out // ''), run_perl($src), 'renders to the same output' or diag $out // $d->gap;

done_testing;
