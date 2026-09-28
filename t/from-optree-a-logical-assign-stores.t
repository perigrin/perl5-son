# ABOUTME: `||=`, `&&=` and `//=` store into their target; each is the value
# ABOUTME: form of the operator followed by an assignment, not a skipped branch.

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

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; diag producer_stderr(); return;
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

# THE GENERIC BRANCH-SKIP STEPPED OVER ALL THREE. They are registered BRANCH
# with no handler, so the walk moved to ->next and the store in the ->other arm
# never happened -- no node, no GAP:
#
#     my $q = $ENV{X} // 0;  $q ||= 99;  print "$q\n"
#       perl 99     emitted  print(($ENV{X} // 0) . "\n")     -> 0
#
# Corpus 077. Each operator is tested on the arm that assigns and the arm that
# does not, because a lowering that always assigns passes half of them.
round_trips(<<'SRC', '||= on a lexical, both arms');
my $f = $ENV{X} // 0;
my $t = $ENV{X} // 5;
$f ||= 99;
$t ||= 99;
print "$f $t\n";
SRC

round_trips(<<'SRC', '&&= on a lexical, both arms');
my $f = $ENV{X} // 0;
my $t = $ENV{X} // 5;
$f &&= 99;
$t &&= 99;
print "$f $t\n";
SRC

round_trips(<<'SRC', '//= on a lexical, both arms');
my $u = $ENV{NO_SUCH_VAR_EVER};
my $d = $ENV{X} // 0;
$u //= 99;
$d //= 99;
print "$u $d\n";
SRC

# THE VALUE OF THE ASSIGNMENT IS THE STORED VALUE, as for `=`.
round_trips(<<'SRC', 'the value of ||= is what it stored');
my $f = $ENV{X} // 0;
my $r = ($f ||= 7);
print "$r $f\n";
SRC

# A TARGET THE HANDLER DOES NOT MODEL MUST NOT BE DROPPED. Round-tripping is
# the requirement; a named refusal is the floor, and silence is the failure.
subtest 'a package scalar target round-trips or refuses by name' => sub {
    my $src = <<'SRC';
our $g = $ENV{X} // 0;
$g ||= 99;
print "$g\n";
SRC
    my $data = graph_of($src);
    if ($data && $data->{methods}{'main::__PROGRAM__'}) {
        my $out = SoN::Deparse->new->render($data);
        is run_perl($out // ''), run_perl($src), 'round-trips'
            or diag $out // '(refused)';
    }
    else {
        like producer_stderr(), qr/GAP: `\|\|=`/, 'refuses naming the operator';
    }
};

done_testing;
