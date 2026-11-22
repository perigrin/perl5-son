# ABOUTME: A string eval whose code is known when B::SoN runs is compiled there, in the eval's scope:
# ABOUTME: a body (an anonymous sub) over the lexicals it names, called inside a block eval's trap.
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

# The producer's graph and everything it said on stderr.
sub produce ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    my $err = do { local (@ARGV, $/) = ("$dir/err"); <> } // '';
    $err =~ s/^\S+ syntax OK\n//mg;
    return (scalar(eval { JSON::PP->new->decode($j) }), $err);
}

sub nodes ($w, $sub) {
    my %n = map { ( $_->{id} => $_ ) } ( $w->{methods}{$sub}{nodes} // [] )->@*;
    return \%n;
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
    my ($data, $err) = produce($src);
    like $err, $why, "$name: refused by name";
}

# THE SHAPE: the eval is a trap (a Region with eval_entry and eval_id) whose
# body is one direct call of the compiled code; the code is a body graph whose
# CellParams are the lexicals it names, handed over as the AnonSub's cells.
{
    my ($w, $err) = produce(q{my $i = 0; eval q{$i = 1}; print "i=$i\n";});
    is $err, '', 'eval q{$i = 1}: the producer says nothing';
    my $n = nodes($w, 'main::__PROGRAM__');
    my ($anon) = grep { $_->{op} eq 'AnonSub' } values %$n;
    ok $anon, 'the compiled code is an AnonSub in the program' or last;
    like $anon->{fields}{name}, qr/\Amain::__PROGRAM__::__EVAL__:1:\d+\z/, 'named for the eval: __EVAL__:LINE:N';
    is $anon->{fields}{captures}, ['$i'], 'it captures the one lexical its code names';
    is $n->{ $anon->{inputs}[0] }{op}, 'MakeCell', 'through the cell the program keeps $i in';
    my ($call) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq $anon->{fields}{name} } values %$n;
    ok $call, 'a direct call of it' or last;
    is $call->{fields}{dispatch_kind}, 'direct', 'direct';
    ok $call->{fields}{string_eval}, 'which says it runs an eval string';
    ok defined $call->{fields}{eval_id}, 'inside an eval';
    my ($region) = grep { $_->{op} eq 'Region' && defined $_->{fields}{eval_id} && !$_->{fields}{catch} } values %$n;
    ok $region, 'the eval is a trap' or last;
    is $region->{fields}{eval_id}, $call->{fields}{eval_id}, 'the call is in that trap';
    is $n->{ $region->{inputs}[0] }{control_in}, $call->{id}, 'and the trap joins after the call (its end clears $@)';
    my ($x) = grep { $_->{op} eq 'Exc' } values %$n;
    is $x && $x->{inputs}, [ $call->{id} ], '... and its catch: the call\'s way out';
    my $body = nodes($w, $anon->{fields}{name});
    ok( ( grep { $_->{op} eq 'CellParam' && $_->{fields}{name} eq '$i' } values %$body ), 'the body names $i through its CellParam');
    ok( ( grep { $_->{op} eq 'CellWrite' } values %$body ), 'and writes it');
    my ($read) = grep { $_->{op} eq 'CellRead' } values %$n;
    ok $read, 'the print after the eval reads $i through its cell';
}

# PERL'S ANSWER, through the graph (Deparse renders it back).
round_trips(q{my $i = 0; eval q{$i = 1}; print "i=$i\n";}, 'an eval writing a file lexical (pvm 292)');
round_trips(q{my $s = "abc"; my $c = q{3*4}; $s =~ s/b/$c/ee; print "$s\n";},
    's///ee of a lexical holding a constant (pvm 290)');
round_trips(q{my $x = 2; my $r = eval q{$x * 3}; print "$r [$@]\n";}, 'the value of the last statement');
round_trips(q{my $x = 2; my $r = eval q{ return $x + 1; 9 }; print "$r\n";}, 'a return leaves the eval with its value');
round_trips(q{my $i = 0; my $r = eval q{$i = 1; die "no\n"; 5}; print defined $r ? $r : 'u', " $i $@";},
    'a die sets $@ and the eval is undef; what the body stored before it stands');
round_trips(q{my $i = 0; $@ = "old"; my $r = eval q{$i + 4}; print "$r [$@]\n";}, 'success clears $@');
round_trips(q{my $i = 1; { my $j = 5; eval q{$j = 7; $i = $j + 1}; print "$j\n" } print "$i\n";}, 'a lexical of a bare block around the eval');
round_trips(q{my $x = 1; our $x = 5; my $r = eval '$x + 0'; print "$r\n";}, 'an our masking a my: the our');
round_trips(q{my $x = 3; my $r = eval q{my $x = 10; $x + 1}; print "$r $x\n";}, 'a my inside the string is its own');
round_trips(q{my $i = 0; eval q{$i = 1}; eval q{$i = $i + 10}; print "$i\n";}, 'two evals over one lexical share its cell');
# A READ BEFORE THE EVAL IN ITS EXPRESSION is of the variable, read when the
# operator runs: after the eval stored it (perl pushes $x itself, not a copy).
round_trips(q{my $x = 1; my $r = $x + eval q{$x = 5; 0}; print "$r $x\n";}, 'an operand the eval stores is read after it');
# (and a closure's call, the same hole: the program's reads were never read again)
round_trips(q{my $x = 1; my $f = sub { $x = 5; 0 }; my $r = $x + $f->(); print "$r $x\n";}, 'an operand a closure stores is read after its call');
round_trips(q{my $i = 0; my $c = $ENV{NO_SUCH_VAR} ? 1 : 0; if ($c) { eval q{$i = 1} } print "$i\n";}, 'an eval in an arm not taken');
round_trips(q{my $x = 1; my $r = eval { eval q{$x = 2; die "in\n"}; $x + 10 }; print "$r $x [$@]\n";}, 'a string eval in a block eval');

# REFUSED BY NAME: perl compiles the string when the eval runs, so a string
# that does not compile sets $@ there, naming (eval N) -- a count of evals run.
refuses(q{my $i = 0; my $r = eval q{$i = }; print defined $r ? 1 : 0, "\n";},
    'a constant string that does not compile', qr/GAP: a string eval whose code does not compile/);
refuses(q{my $i = 0; eval q{die "no"}; print $@;},
    'a die whose message names its place, (eval N)', qr/GAP: a string eval .*holding a die/);
refuses(q{my $i = 0; eval q{warn "w\n"}; print "x\n";},
    'a warn in the string', qr/GAP: a string eval .*holding a warn/);
refuses(q{sub f { my $i = 1; eval q{$i = shift}; $i } print f(5), "\n";},
    'a string eval inside a sub', qr/GAP: a string eval .*inside a sub/);
refuses(q{my $n = $ENV{X} // 2; my $r = eval "$n + 1"; print "$r\n";},
    'a string built at run time (pvm 291)', qr/GAP: a string eval of code made at run time/);
refuses(q{my $i = 0; for my $k (1, 2) { eval q{$i = $i + $k} } print "$i\n";},
    'a string eval in a loop', qr/GAP: a string eval .*loop/);
# A NAME THE FILE DECLARES TWICE: the body is matched to the slot in scope,
# but a consumer that shares a closure's variables by name cannot tell them
# apart (closures have the same hole).
refuses(q{my $i = 1; { my $i = 5; eval q{$i = 7} } print "$i\n";},
    'a name the file declares twice', qr/GAP: a string eval .*declares more than once/);
refuses(q{my $x = 1; my $r = eval '$x + 0'; our $x = 5; print "$r\n";},
    'a my and an our of one name', qr/GAP: a string eval .*declares more than once/);
refuses(q|my $x = 1; my $r = eval q[1 }; $x = 5; { 2]; print defined $r ? "def" : "undef", " $x\n";|,
    'a string whose braces leave its body', qr/GAP: a string eval .*braces leave its body/);
refuses(q{my $x = 1; my $r = eval q{BEGIN { print "begin\n" } $x + 1}; print "$r\n";},
    'a BEGIN in the string', qr/GAP: a string eval .*holding `BEGIN`/);
refuses(q{my $x = 1; @ARGV = (5, 6); my $r = eval q{shift}; print "$r @ARGV\n";},
    'a bare shift (of @_ in the body, of @ARGV in the eval)', qr/GAP: a string eval .*holding a shift/);
refuses(q{my $x = 2; my @r = eval q{($x, 3)}; print "@r\n";},
    'an eval in list context', qr/GAP: a string eval .*in list context/);
refuses(q{use warnings; my $x = 1; my $r = eval q{$x + 1}; print "$r\n";},
    'an eval where warnings are on', qr/GAP: a string eval .*warnings are on/);
refuses(q{my @a = (1, 2); eval q{push @a, 3}; print "@a\n";},
    'a string naming a lexical array', qr/GAP: a string eval .*naming the lexical array or hash \@a/);
refuses(q{my $c = q{3*4}; $c = q{1+1}; my $r = eval $c; print "$r\n";},
    'a lexical written twice is no constant', qr/GAP: a string eval of code made at run time/);

done_testing;
