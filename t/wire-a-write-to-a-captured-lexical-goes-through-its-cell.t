# ABOUTME: Every write to a lexical a closure or a string eval captured goes through its cell:
# ABOUTME: op=, ++/--, in the body and in the scope that made the cell; or it is refused by name.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub produce ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    my $err = do { local (@ARGV, $/) = ("$dir/err"); <> } // '';
    $err =~ s/^\S+ syntax OK\n//mg;
    return (scalar(eval { JSON::PP->new->decode($j) }), $err);
}

sub ops_of ($w, $re) {
    return map { $_->{op} } map { ( $w->{methods}{$_}{nodes} // [] )->@* } grep { /$re/ } keys $w->{methods}->%*;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ($data, $err) = produce($src);
    is $err, '', "$name: the producer says nothing";
    my $d = SoN::Deparse->new;
    my $out = $data ? $d->render($data) : undef;
    unless (defined $out) { fail "$name: renders"; diag $d->gap // $err; return }
    is run_perl($out), $want, "$name: perl's answer" or diag "--- emitted ---\n$out";
}

sub refuses ($src, $name, $why) {
    my (undef, $err) = produce($src);
    like $err, $why, "$name: refused by name";
}

# THE SHAPE. `$n *= 3` in a string eval's body read the CellParam ITSELF (the
# cell, not its value) and stored nothing: the body was `1`, and the program
# printed 1 where perl prints 3. The read is a CellRead, the store a CellWrite.
{
    my ($w, $err) = produce(q{my $n = 1; eval q{$n *= 3; 1}; print "$n\n";});
    is $err, '', 'eval q{$n *= 3; 1}: the producer says nothing';
    my @body = ops_of($w, qr/__EVAL__/);
    ok( ( grep { $_ eq 'CellRead' } @body ), 'the body reads $n through its cell');
    ok( ( grep { $_ eq 'CellWrite' } @body ), 'and writes the product back through it');
}
{
    my ($w, $err) = produce(q{my $n = 1; my $f = sub { $n }; $n *= 3; print $f->(), "\n";});
    is $err, '', 'op= after the closure: the producer says nothing';
    my @prog = ops_of($w, qr/\Amain::__PROGRAM__\z/);
    ok( ( grep { $_ eq 'CellWrite' } @prog ), 'the scope that made the cell writes through it');
}

# PERL'S ANSWER, through the graph, for each op= spelling, in the three places a
# captured lexical is written: a string eval's body, a closure's body, and the
# scope that made the cell after the closure exists.
my @op_assign = (
    [1, '$n *= 3'], [1, '$n += 3'], [1, '$n -= 3'], [7, '$n **= 2'], ['"a"', '$n x= 3'],
    ['"a"', '$n .= "b"'], [7, '$n |= 8'], [7, '$n <<= 2'], [7, '$n %= 4'], [1, '$n /= 2'],
);
for my $c (@op_assign) {
    my ($init, $st) = @$c;
    round_trips(qq{my \$n = $init; my \$f = sub { $st; 1 }; \$f->(); \$f->(); print "\$n\\n";},
        "a closure: $st");
    round_trips(qq{my \$n = $init; my \$f = sub { \$n }; $st; print \$f->(), "\\n";},
        "the scope that made the cell: $st");
    round_trips(qq{my \$n = $init; my \$f = sub { \$n }; my \$r = ($st); print \$f->(), " \$r\\n";},
        "its value: $st");
}
# A string eval allows the ops its allow-list names (not %, /, |=, <<=).
for my $c (@op_assign[0 .. 5]) {
    my ($init, $st) = @$c;
    round_trips(qq{my \$n = $init; eval q{$st; 1}; print "\$n\\n";}, "a string eval: $st");
}
round_trips(q{my $n = 1; my $r = $n + eval '$n *= 3; 1'; print "$r $n\n";},
    'an operand the eval op-assigns is read after it');
round_trips(q{my $n = 1; my $r = eval q{$n *= 3}; print "$r $n\n";}, "the eval's value is the product");
round_trips(q{my $n = 1; eval q{$n = 2}; eval q{$n *= 5; 1}; print "$n\n";}, 'two evals, = then *=');
round_trips(q{my $n = 1; my $f = sub { for my $i (1 .. 3) { $n *= 2 } 1 }; $f->(); print "$n\n";},
    'op= in a loop in a closure');
round_trips(q{my $n = 1; my $f = sub { $n += 2; $n }; my $r = $f->() + $f->(); print "$r $n\n";},
    'a closure that op-assigns and returns the variable');

# ++ AND -- IN THE SCOPE THAT MADE THE CELL: the MakeCell is the handle there,
# as the CellParam is in the body. Rebinding the slot left the cell at 1.
for my $c ([1, '$n++'], [1, '++$n'], [1, '$n--'], [1, '--$n'], ['"Az"', '$n++']) {
    my ($init, $st) = @$c;
    round_trips(qq{my \$n = $init; my \$f = sub { \$n }; my \$r = $st; print \$f->(), " \$r\\n";},
        "the scope that made the cell: $st");
}

# ||= &&= //=: the test branched on the handle itself (an If over the MakeCell,
# which chalk emitted as a call of nothing) and the store went to a pad slot.
for my $c ([0, '$n ||= 5'], [7, '$n ||= 5'], [1, '$n &&= 5'], [0, '$n &&= 5'], ['undef', '$n //= 5'], [3, '$n //= 5']) {
    my ($init, $st) = @$c;
    round_trips(qq{my \$n = $init; my \$f = sub { $st; 1 }; \$f->(); \$f->(); print "\$n\\n";},
        "a closure: $st over $init");
    round_trips(qq{my \$n = $init; my \$f = sub { \$n }; my \$r = ($st); print \$f->(), " \$r\\n";},
        "the scope that made the cell: $st over $init");
}

# s/// AND tr/// IN THE CLOSURE THAT CAPTURED THEIR SUBJECT: the op's targ named
# the body's own pad slot, so the substitution went to a slot nobody reads and
# the caller's variable kept its value. Refused until it is stored through the
# cell. (In the scope that made the cell the slot IS the variable.)
refuses(q{my $n = "abc"; my $f = sub { $n =~ s/b/X/; 1 }; $f->(); print "$n\n";},
    's/// in a closure on what it captured', qr/GAP: s\/\/\/ on a lexical .*captured/);
refuses(q{my $n = "abc"; my $f = sub { $n =~ tr/a-c/A-C/; 1 }; $f->(); print "$n\n";},
    'tr/// in a closure on what it captured', qr/GAP: tr\/\/\/ on a lexical .*captured/);
round_trips(q{my $n = "abc"; my $f = sub { $n }; $n =~ s/b/X/; print $f->(), "\n";},
    's/// in the scope that made the cell');
round_trips(q{my $n = "abc"; my $f = sub { $n }; $n =~ tr/a-c/A-C/; print $f->(), "\n";},
    'tr/// in the scope that made the cell');

done_testing;
