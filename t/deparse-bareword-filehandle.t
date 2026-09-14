# ABOUTME: A bareword filehandle is a `glob` Constant, and its spelling is the bareword.
# ABOUTME: open/close/readline/print all take it, so a wrong spelling breaks the file, not just the name.

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
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
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

# A BAREWORD FILEHANDLE IS A `glob` CONSTANT holding the bare name. Measured on
# comp/line_debug.t and comp/multiline.t:
#
#     Constant(9) const_type=glob value=AUX
#       read by Call(open), Call(close), Call(readline)
#     Constant(14) const_type=glob value=TRY
#       read by Call(open), Call(close), Call(readline), Print(has_filehandle)
#
# so it is an operand of every file operation, not a decoration. Quoting it or
# emitting it as a string would open a file NAMED "AUX" rather than use the
# handle -- a program that runs and does the wrong thing.
#
# THE ROUND TRIP WRITES AND READS BACK, so a handle that silently went
# elsewhere shows up as missing content rather than as a rendering error.
#
# NO `or die` HERE, idiomatic though it is: it builds an Unwind, which is
# a separate refusal, and a case that fails for two reasons proves neither.
subtest 'a bareword filehandle round-trips' => sub {
    round_trips(<<'SRC', 'open, print, close, read back');
my $f = "bw.$$.tmp";
open(TRY, ">$f");
print TRY "line one\n";
print TRY "line two\n";
close(TRY);
open(TRY, "<$f");
my @got = <TRY>;
close(TRY);
unlink $f;
print "count=", scalar(@got), "\n";
print @got;
SRC
};

# TWO HANDLES AT ONCE, so a spelling that collapsed them to one name would
# show as the wrong content rather than as a syntax error.
#
# LIST CONTEXT, NOT SCALAR. `my $r = <FH>` loses its binding entirely in the
# producer -- measured, the graph holds an unbound `PadAccess $s` and the
# readline's value reaches nothing -- which is a separate defect with its own
# test (t/from-optree-scalar-readline-binds.t). A case that fails for two
# reasons proves neither.
subtest 'two bareword handles stay distinct' => sub {
    round_trips(<<'SRC', 'two handles');
my $a = "bwa.$$.tmp";
my $b = "bwb.$$.tmp";
open(AAA, ">$a"); print AAA "from A\n"; close(AAA);
open(BBB, ">$b"); print BBB "from B\n"; close(BBB);
open(AAA, "<$a"); my @ra = <AAA>; close(AAA);
open(BBB, "<$b"); my @rb = <BBB>; close(BBB);
unlink $a; unlink $b;
print "a=@ra";
print "b=@rb";
SRC
};

done_testing;
