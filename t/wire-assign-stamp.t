# ABOUTME: An assignment's value is the value it stored, so it takes the RHS stamp.
# ABOUTME: `$x = $y = 5` works precisely because an assign yields the stored value.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($src, $name, %opt) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $filter = $opt{no_filter} ? '' : ',package=main';
    my $json = qx{$PERL -Ilib -MO=SoN,json$filter $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub assigns ($wire, $graph) {
    my $g = $wire->{methods}{$graph} or return ();
    return grep { $_->{op} eq 'Assign' } ($g->{nodes} // [])->@*;
}

# THE DEFECT. An assignment's VALUE is the value it stored -- that is why
# `$x = $y = 5` works, and SoN::IR::Value's own comment says so ("an
# assignment's result is the stored value"). So its stamp is the RHS stamp.
# 23 of the 125 remaining wire Unknowns were Assigns whose inputs were BOTH
# already stamped.
subtest 'an element store takes the stored value type' => sub {
    my $wire = wire_for('my @a = (1, 2, 3); $a[0] = 42; say($a[0]);', 'elem');
    my @as = assigns($wire, 'main::__PROGRAM__');
    ok @as >= 1, 'an Assign exists' or return;
    is $as[0]{stamp}, 'Int', 'storing an Int yields Int';
};

# BILATERAL. Storing a Str must give Str -- a hardcoded Int would pass above.
subtest 'storing a Str yields Str' => sub {
    my $wire = wire_for('my @a = ("x", "y"); $a[0] = "z"; say($a[0]);', 'elem_str');
    my @as = assigns($wire, 'main::__PROGRAM__');
    ok @as >= 1, 'an Assign exists' or return;
    is $as[0]{stamp}, 'Str', 'storing a Str yields Str';
};

# IT IS THE RHS, NOT THE LVALUE. This is the case that separates "takes the
# stored value" from "takes either operand": the target slot and the stored
# value have DIFFERENT types here, and the answer must be the stored one.
subtest 'the stamp follows the RHS, not the target' => sub {
    my $wire = wire_for('my @a = (1, 2, 3); $a[0] = "s"; say($a[0]);', 'retype');
    my @as = assigns($wire, 'main::__PROGRAM__');
    ok @as >= 1, 'an Assign exists' or return;
    is $as[0]{stamp}, 'Str',
        'storing a Str into an Int slot yields Str, not Int';
};

# A field store, the other shape in the corpus.
subtest 'a field store takes the stored value type' => sub {
    my $src = 'use feature "class"; no warnings "experimental::class";
class Counter { field $n = 0; method inc { $n = $n + 1; return $n } }
my $c = Counter->new; say($c->inc);';
    my $wire = wire_for($src, 'field', no_filter => 1);
    my @as = assigns($wire, 'Counter::inc');
    ok @as >= 1, 'an Assign exists' or return;
    is $as[0]{stamp}, 'Int', 'storing an Int into a field yields Int';
};

# ONLY PROPAGATES. An untyped RHS leaves the assignment untyped.
subtest 'an untyped RHS leaves the assign Unknown' => sub {
    my $wire = wire_for('sub f { my $n = shift; my @a = (1,2); $a[0] = $n; return $a[0] }
print f(3), "\n";', 'unknown_rhs');
    my @as = assigns($wire, 'main::f');
    ok @as >= 1, 'an Assign exists' or return;
    is $as[0]{stamp}, 'Unknown', 'an untyped stored value leaves the assign Unknown';
};

done_testing;
