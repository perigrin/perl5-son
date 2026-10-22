# ABOUTME: An element read at the top of a loop iteration, used after a call
# ABOUTME: passed an element of the same array, reads the value before the call.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
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

# THE READ IS BOUND AT THE TOP OF THE BODY. A call may write any element it is
# passed through $_[0], so `$t[$i+1]`, spelled where `$next` is used after
# `emit($t[$i])`, would read what the call left. Read into a per-iteration
# temporary first, it is the value perl read (chalk's
# LLVM::Context::_emit_read_slot_as, which refused).
round_trips(<<'SRC', 'an element read used after a call passed an element');
sub emit { print "$_[0]\n" }
sub f {
    my @t = map { "L$_" } 0 .. 2;
    for my $i (0 .. $#t) {
        my $next = $i < $#t ? $t[$i+1] : 'undef';
        emit($t[$i]);
        emit("br $next");
    }
}
f();
SRC
round_trips(<<'SRC', 'and the call does write it');
sub bump { $_[0] = uc $_[0] }
sub f {
    my @t = qw(a b c);
    my $s = '';
    for my $i (0 .. $#t) {
        my $v = $t[$i];
        bump($t[$i]);
        $s .= "$v$t[$i] ";
    }
    return $s;
}
print f(), "\n";
SRC

# AFTER A STORE MADE IN THE ITERATION -- `my $repr = $readings[$i]` into a
# lexical a method call may see -- the read is bound right after that store.
round_trips(<<'SRC', 'an element read after a store to a lexical, before a call passed an element');
package C; sub new { bless { n => 0 }, shift } sub _fresh_label { $_[1] . $_[0]{n}++ }
sub _new_block { print "B $_[1]\n" } sub _set_terminator { print "T $_[1]\n" } sub _emit_coercion { "c$_[2]" }
sub f {
    my ($self, $to, @readings) = @_;
    my $val = '';
    my @test_lbls = map { $self->_fresh_label('t' . $_ . '.') } 0 .. $#readings;
    for my $i (0 .. $#readings) {
        my $repr = $readings[$i];
        my $next = $i < $#readings ? $test_lbls[$i+1] : 'undef';
        $self->_new_block($test_lbls[$i]);
        $self->_set_terminator("br $repr $next");
        $val = $self->_emit_coercion($val, $repr, $to) if $repr ne $to;
    }
    return $val;
}
package main; print C->new->f('Str', qw(Int Num Str)), "\n";
SRC

# NOT WHEN THE LOOP'S TEST READS IT TOO: the test runs before the body, and
# bound there it read the pass before's temporary -- `while ($a[0] < 3)`
# ran a fourth time. Refused, or right; never that.
{
    my $src = q{sub bump { $_[0] = $_[0] + 1 } sub f { my @a = (0); my $s = ""; while ($a[0] < 3) { my $v = $a[0]; bump($a[0]); $s .= "$v$a[0],"; } return $s } print f(), "\n";};
    my $out = SoN::Deparse->new->render(graph_of($src));
    ok !defined $out || run_perl($out) eq run_perl($src),
        "a read the while test shares is not read from the pass before";
}

# A CALL PASSED A REFERENCE writes through it: `$info->{n}` read before
# `emit($info)` was spelled after it, and printed the call's `z` for perl's
# `x` (chalk's Perl::Target::C::_generate_c_files reads
# `$info->{static_name}` before `_emit_init_expr`). Read where it is: right
# after the container is made in the iteration.
round_trips(<<'SRC', 'an element read through a reference, before a call passed the reference');
my %v = (a => {n => "x"}, b => {n => "y"}); sub vars { \%v } sub emit { my $h = $_[0]; $h->{n} = "z"; "e" }
sub f { my @l; for my $k (sort keys vars()->%*) { next unless exists vars()->{$k}; my $info = vars()->{$k}; my $s = $info->{n}; my $e = emit($info); push @l, "$s=$e" } "@l" }
print f(), "\n";
SRC

# USED ONLY IN AN ARM AFTER THE CALL, it is still read before the call: its
# version says so, and no `if` comes first (chalk's _generate_c_files pushes
# `"$sname = $init_expr"` only `if defined $init_expr`).
round_trips(<<'SRC', 'an element read through a reference, used in an arm after the call');
my %v = (a => {n => "x"}, b => {n => "y"}); sub vars { \%v } sub emit { my $h = $_[0]; $h->{n} = "z"; $_[1] }
sub f { my @l; for my $k (sort keys vars()->%*) { my $info = vars()->{$k}; my $s = $info->{n}; my $e = emit($info, $k eq "a" ? 1 : undef); push @l, "$s=$e" if defined $e } "@l" }
print f(), "\n";
SRC

# A CALL HANDED `\@a` writes its elements: `$a[$i + 1]`, read before
# `w(\@a, ...)` and used after it, printed the call's `z` (`zz` for perl's
# `bc`). Nothing it reads is made in the iteration, so it is read at the top
# of the body -- an element of a named array neither dies nor autovivifies.
round_trips(<<'SRC', 'an element of a named array read before a call handed a reference to it');
sub w { $_[0][$_[1]] = "z"; 1 } sub f { my @a = qw(a b c); my $s = ""; my $i = 0; while ($i < 2) { my $v = $a[$i + 1]; if ($v ne "q") { w(\@a, $i + 1) } $s .= $v; $i++ } "$s @a" } print f(), "\n";
SRC

done_testing;
