# ABOUTME: `$s++` on a string is perl's magic increment ("Az" -> "Ba"), not
# ABOUTME: Add($s, 1); a numeric operand keeps the Add it has always had.

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

sub ops_of ($src) {
    my $data = graph_of($src) or return [];
    return [ map { $_->{op} } $data->{methods}{'main::__PROGRAM__'}{nodes}->@* ];
}

# INCREMENT LOWERED TO Add(old, 1), exact for a number and wrong for a string
# perl increments magically -- measured, corpus 212:
#
#     "Az"++  "Ba"      "zz"++  "aaa"     "a9"++  "b0"
#     ours    1         1       1         (Add coerced each to 0)
round_trips(<<'SRC', 'post-increment of strings');
my $a = $ENV{X} // "Az";
my $b = $ENV{Y} // "zz";
my $c = $ENV{Z} // "a9";
$a++;
$b++;
$c++;
print "$a $b $c\n";
SRC

round_trips(<<'SRC', 'pre-increment of a string, used as a value');
my $s = $ENV{X} // "Zz";
my $t = ++$s;
print "$t $s\n";
SRC

round_trips(<<'SRC', 'post-increment of a string yields the old value');
my $s = $ENV{X} // "az";
my $old = $s++;
print "$old $s\n";
SRC

# A NUMERIC OPERAND KEEPS ITS Add -- the counter every loop has, and the node
# chalk already lowers.
subtest 'an Int counter still increments with Add' => sub {
    my $ops = ops_of(<<'SRC');
my $i = 0;
$i++;
print "$i\n";
SRC
    ok( (grep { $_ eq 'Add' } @$ops), 'Add is present' );
    ok( !(grep { $_ eq 'Increment' } @$ops), 'no Increment' );
};

# DECREMENT IS NEVER MAGIC in perl ("aa"-- is -1), so it keeps Subtract.
round_trips(<<'SRC', 'decrement of a string is numeric');
my $s = $ENV{X} // "aa";
$s--;
print "$s\n";
SRC

done_testing;
