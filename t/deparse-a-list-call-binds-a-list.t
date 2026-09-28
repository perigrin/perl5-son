# ABOUTME: A call perl compiled in list context binds an array temporary, even
# ABOUTME: when the callee's inferred stamp is a scalar kind such as Undef.

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

# A BARE `return` IN LIST CONTEXT IS THE EMPTY LIST. The callee's inferred
# stamp is Undef, and the binding was chosen from the stamp alone:
#
#     my $eff2 = bare();
#     my @empty = ($eff2);        one undef element; perl has none
#
# The Call's `want` field records the context perl compiled it in, and it is
# `list` here. Corpus 031.
round_trips(<<'SRC', 'a bare return in list context');
sub bare { return }
my @empty = bare();
print scalar(@empty), "\n";
SRC

# `caller` AT FILE SCOPE is the empty list in list context and undef in
# scalar. Corpus 084.
round_trips(<<'SRC', 'caller at file scope, both contexts');
my $s = caller;
my @l = caller;
my @one = $s;
print scalar @one, " ", scalar @l, "\n";
SRC

# localtime IS THE SAME SHAPE: nine fields in list context, a date string in
# scalar.
round_trips(<<'SRC', 'localtime in both contexts');
my @t = localtime(0);
my $s = gmtime(0);
print scalar(@t), " $s\n";
SRC

# THE SCALAR CALL KEEPS ITS SCALAR TEMPORARY. Same callee, scalar context.
round_trips(<<'SRC', 'a bare return in scalar context');
sub bare { return }
my $x = bare();
print defined($x) ? "def" : "undef", "\n";
SRC

done_testing;
