# ABOUTME: `scalar(@a)` passed to a call is the array's count, for a lexical, a pushed
# ABOUTME: array and a class field -- not the array, flattened into the arguments.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
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

# A CALL ARGUMENT IS OPf_MOD, and the count rule skipped every padav that
# was REF or MOD -- written for a foreach source and a push or shift operand,
# which are both. `F->new(ix => scalar(@fields))` passed the elements: chalk's
# MOP::Class::declare_field died "Odd number of arguments".
round_trips(<<'SRC', 'scalar of a lexical and a pushed array, as arguments');
sub new { my ($c, %o) = @_; return $o{ix} }
my @a = (1, 2, 3); my @b; push @b, 4, 5;
print main->new(ix => scalar(@a)), main->new(ix => scalar(@b)), "\n";
SRC
round_trips(<<'SRC', 'scalar of a field array, as an argument');
use v5.42; use experimental 'class';
class F { field $ix :param; method ix { $ix } }
class C {
    field @fields;
    method add ($n, %o) { my $f = F->new(ix => scalar(@fields), %o); push @fields, $f; return $f }
}
my $c = C->new; $c->add("a"); print $c->add("b")->ix, "\n";
SRC
round_trips(<<'SRC', 'an array passed whole is still its elements');
sub n { scalar @_ }
my @a = (1, 2, 3);
print n(@a), n(scalar(@a)), "\n";
SRC

done_testing;
