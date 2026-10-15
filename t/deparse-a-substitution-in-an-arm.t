# ABOUTME: An s/// inside an if arm runs only when the arm does, and a read after the
# ABOUTME: join sees the substituted value on that path and the original on the other.

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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


# The arm walker had no s/// of its own: the op fell to the generic builtin
# Call, holding the replacement string and nothing else, hung off the
# control before the guard with no If -- "a control node with 2 successors".
# chalk's LLVM::Context::_compile_regex_pattern strips a trailing anchor so.
round_trips(<<'P', 'an s/// in a one-armed if');
sub f { my ($p) = @_; if (length($p) == 3) { $p =~ s/c$//; } return $p }
print f("abc"), f("abbc"), f("x"), "\n";
P

round_trips(<<'P', 'an s/// guarded by a match whose capture is read');
sub f {
    my ($p) = @_;
    my $e = 0;
    if ($p =~ /(\\*)\$$/ && length($1) % 2 == 0) { $e = 1; $p =~ s/\$$//; }
    return "$e:$p";
}
print f("ab\$"), f("a\\\$"), f("x"), "\n";
P

round_trips(<<'P', 'an s/// with a replacement, beside an else');
sub f { my ($p) = @_; if ($p =~ /c/) { $p =~ s/c/d/g; } else { $p .= "!" } return $p }
print f("acbc"), f("ab"), "\n";
P

round_trips(<<'P', 'an s/// after a call in the arm');
sub f { my ($p) = @_; if (length($p) == 3) { print "x"; $p =~ s/c$//; } return $p }
print f("abc"), f("abbc"), "\n";
P

round_trips(<<'P', 'a statement-modifier s///');
sub f { my ($p) = @_; $p =~ s/^\^// if $p =~ /^\^/; return $p }
print f("^ab"), f("ab"), "\n";
P

# A /r ON AN ELEMENT writes nothing, so its subject is a value: refused as
# "not a named scalar", which the arm walk now reached where it used to drop
# the s/// whole (chalk's IR::Analysis strips sigils from `$f->{name}` so).
round_trips(<<'P', 'an s///r on an element, in an arm');
sub f { my ($f) = @_; if ($f) { my $x = $f->{name} =~ s/^[\$\@\%]//r; return "$x $f->{name}" } "-" }
print f({name => "\$ab"}), f(0), "\n";
P

round_trips(<<'P', 'an s///r on an element and on an array element, straight-line');
my $h = {n => "aXa"};
my @a = ("xa");
my $c = ($h->{n} =~ s/a/b/gr) . "!";
my $y = uc($a[0] =~ s/x//r);
print "$c $h->{n} $y @a\n";
P

done_testing;
