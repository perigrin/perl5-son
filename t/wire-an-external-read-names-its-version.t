# ABOUTME: An external read -- the clock, a file test, a tie's object -- names the memory version it
# ABOUTME: is read at (Q13: the world is on the one memory chain).

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;
use SoN::Verify;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# reads_at_versions($rule_re, [what, src], ...): each wire has no violation of
# the rules matched, and the deparser's rendering prints what perl prints.
sub reads_at_versions ( $rule, @cases ) {
    for my $case (@cases) {
        my ( $what, $src ) = $case->@*;
        subtest $what => sub {
            my $data = graph_of($src) or return fail 'a wire';
            my @bad  = grep { $_->{rule} =~ $rule } SoN::Verify::verify($data)->{violations}->@*;
            is [ map { "$_->{graph} $_->{op}#$_->{node} $_->{rule} $_->{detail}" } @bad ], [], 'every read names a version';
            my $d   = SoN::Deparse->new;
            my $out = $d->render($data);
            ok defined $out, 'the deparser renders it' or diag $d->gap;
            is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
        };
    }
}

# Wire v2 stage 7, the `external` row of the read rule (V6), as Q13 decided.
reads_at_versions( qr/\Aread-unversioned:external\z/,
    [ 'time either side of a print (ef17)', q{my $a = time; print ""; my $b = time; print $b - $a < 5 ? "ok\n" : "no\n";} ],
    [ 'a file test (ef3)', q{print -e "/" ? "e" : "n", -d "/" ? "d" : "f", "\n";} ],
    [ 'tied of a tied scalar (corpus 416)',
        q{package T; sub TIESCALAR { bless {}, shift } sub FETCH { 7 } package main; tie my $t, "T"; print ref(tied $t), " $t\n";} ],
    [ 'time after an eval that dies (corpus 006): its memory is the eval join',
        q{our $e; eval { $e = 1; die "x\n" }; my $t = time; print "-t", $t > 1000000000 ? 1 : 0, "\n";} ],
    [ 'localtime of a constant (corpus 312)', q{my @t = localtime(0); print scalar(@t), "\n";} ],
);

done_testing;
