# ABOUTME: The text after __DATA__ or __END__ reaches the wire, and the emitted
# ABOUTME: program carries it, so a <DATA> read returns what the source held.

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

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
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

# THE DATA SECTION IS NOT IN THE OPTREE -- it is text after the program that
# perl leaves open on main::DATA. The graph reads the handle and nothing
# says what it holds, so the emission read an empty handle. Corpus 166, 167.
round_trips(<<'SRC', 'a __DATA__ section');
my @lines = <DATA>;
print @lines;
__DATA__
one
two
SRC

# IT IS TEXT, NOT CODE: an unbalanced line after the marker is data.
round_trips(<<'SRC', 'a __DATA__ section that is not valid perl');
my @lines = <DATA>;
print @lines;
__DATA__
sub not_compiled { $x <=> }
q{ unbalanced
SRC

# __END__ IN THE MAIN SCRIPT OPENS DATA TOO.
round_trips(<<'SRC', 'an __END__ section');
print <DATA>;
__END__
from the end section
SRC

# NO SECTION, NO MARKER: the emission must not invent one.
subtest 'a program without a data section has none on the wire' => sub {
    my $data = graph_of(qq{print "x\\n";\n});
    ok !exists $data->{data_section}, 'no data_section key';
};

done_testing;
