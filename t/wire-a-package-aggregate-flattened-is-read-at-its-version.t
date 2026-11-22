# ABOUTME: A package array or hash flattened into a list is read at a memory version (an
# ABOUTME: EntryDef with mem_in), not handed on as its name or as the literal last stored in it.

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

# W10 (wire v2 stage 7, the `package` and `package-aggregate-literal` rows):
# `our @st = (1); my @c = (@st, 2); @st = ()` handed the list the literal last
# stored in @st, which a consumer takes for the global itself and reads at the
# list's first use -- after the clear. The read is the global at the version
# before the clear.
for my $case (
    [ 'nv1: a package array flattened, then cleared', q{our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";} ],
    [ 'nv4: flattened after a constant, then stored',  q{our @g = (1,2); my @c = (0, @g); @g = (7); print "@c|@g\n";} ],
    [ 'nv5: a package hash flattened, then cleared',   q{our %g = (a => 1); my @k = (%g); %g = (); print scalar(@k), "\n";} ],
    [ 'nv7: flattened in a sub, then cleared',
        q{our @g = (1,2); sub cp { my @c = (@g, 0); @g = (); return scalar @c } print cp(), scalar(@g), "\n";} ],
    [ 'nv8: flattened into its own local',
        q{our @g = (1); sub t { local @g = (@g, 2); return scalar @g } print t(), scalar(@g), "\n";} ],
    [ 'nv14: returned in a list', q{our @g = (1,2); sub f { return (@g, 9) } my @r = f(); @g = (); print "@r\n";} ],
) {
    my ( $what, $src ) = $case->@*;
    subtest $what => sub {
        my $data = graph_of($src) or return fail 'a wire';
        my @bad  = grep { $_->{rule} =~ /\Aread-unversioned:package/ } SoN::Verify::verify($data)->{violations}->@*;
        is [ map { "$_->{graph} $_->{op}#$_->{node} $_->{detail}" } @bad ], [], 'every read of the package aggregate names a version';
        my $d   = SoN::Deparse->new;
        my $out = $d->render($data);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

done_testing;
