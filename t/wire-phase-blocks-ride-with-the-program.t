# ABOUTME: BEGIN and END blocks -- written out or implied by `use` -- reach the
# ABOUTME: wire in order and the emission runs them at the same phase.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

# -q, as the censuses pass it: O.pm then captures what a BEGIN block prints
# while compiling, instead of letting it land in front of the JSON.
sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
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

# A BEGIN OR END BLOCK IS NOT IN THE PROGRAM'S OPTREE. BEGIN runs while the
# file compiles and is freed; END is queued. O.pm's B::save_BEGINs keeps
# them for a backend, and nothing read them -- the emission ran only the
# main line. Corpus 070.
round_trips(<<'SRC', 'BEGIN and END run at their phases');
END { print "end\n" }
BEGIN { print "begin\n" }
print "main\n";
SRC

# `use` IS A BEGIN BLOCK: require, then import. With `()` there is no import.
# Corpus 125 and 126.
round_trips(<<'SRC', 'use with the default import');
use POSIX;
print "POSIX loaded: ", ($INC{"POSIX.pm"} ? "yes" : "no"), "\n";
print "floor imported: ", ($main::{"floor"} ? "yes" : "no"), "\n";
SRC

round_trips(<<'SRC', 'use with an empty import list');
use POSIX ();
print "POSIX loaded: ", ($INC{"POSIX.pm"} ? "yes" : "no"), "\n";
print "floor imported: ", ($main::{"floor"} ? "yes" : "no"), "\n";
SRC

# ONLY THE PROGRAM'S OWN BLOCKS. begin_av also holds every BEGIN of every
# module the program loaded -- POSIX, Fcntl, Exporter, Carp -- and those
# belong to the modules.
subtest 'a loaded module brings no phase blocks of its own' => sub {
    my $data = graph_of(qq{use POSIX ();\nprint "x\\n";\n});
    my @blocks = ( $data->{phase_blocks} // [] )->@*;
    is scalar(@blocks), 1, 'one block: the use';
};

done_testing;
