# ABOUTME: A package scalar operand is the variable itself, not a copy: a call or a store in a
# ABOUTME: later operand of the same op is what the op reads, for print, join, lists, + and . alike.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

# THE DEFECT (wire v2 stage 5, both wires). perl pushes `$g` itself on the
# stack, so the op reads it when the op runs, after every later operand:
#
#     our $g; sub f { $g = $_[0] + 1; $_[0] } print f(1), $g, f(0), $g;   perl 1101
#
# The walk read $g where its op stood, at f(1)'s version, and said 1201. A
# lexical operand was already read again after the later operands
# (_reread_alias_operand_stored_later); a package scalar was refused for a
# direct store and not seen at all for a call.

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

my $f = 'our $g = 0; sub f { $g = $_[0] + 1; $_[0] } ';

# A CALL IN A LATER OPERAND that writes the package scalar.
round_trips($f . 'print f(1), $g, f(0), $g; print "\n";',                      'print');
round_trips('use feature "say"; ' . $f . 'say f(1), $g, f(0), $g;',              'say');
round_trips($f . 'print join(",", f(1), $g, f(0), $g), "\n";',                  'join');
round_trips($f . 'my @a = (f(1), $g, f(0), $g); print "@a\n";',                  'a list assignment');
round_trips($f . 'my ($a, $b, $c, $d) = (f(1), $g, f(0), $g); print "$a$b$c$d\n";', 'into scalars');
round_trips($f . 'my @a = [f(1), $g, f(0), $g]; print "@{$a[0]}\n";',            'an anonymous array');
round_trips($f . 'my @a; push @a, f(1), $g, f(0), $g; print "@a\n";',            'push');
round_trips($f . 'sub k { return (f(1), $g, f(0), $g) } my @a = k(); print "@a\n";', 'a returned list');
round_trips($f . 'sub k { if ($_[0]) { return (f(1), $g, f(0), $g) } 5 } my @a = k(1); print "@a\n";',
    'a return in an arm');
round_trips($f . 'sub k { for my $i (1) { return (f(1), $g, f(0), $g) } 5 } my @a = k(); print "@a\n";',
    'a return in a loop');
round_trips('my $g = 0; sub f { $g = $_[0] + 1; $_[0] } sub k { return (f(1), $g, f(0), $g) } my @a = k(); print "@a\n";',
    'a returned list, the lexical form');
round_trips($f . 'my $s = f(1) . $g . f(0) . $g; print "$s\n";',                'a concatenation');
round_trips($f . 'print $g, f(1), "\n";',                                        'read before the call');
round_trips('our $g = 1; sub f { $g = 5; 0 } print $g + f(), "\n";',             'an addition');
round_trips('our $g = "a"; sub f { $g = "b"; "" } print $g . f(), "\n";',        'a binary concat');
round_trips('our $g = 1; sub f { $g = 5; 0 } sub h { return $g + f() } print h(), " $g\n";', 'in a sub');

# A DIRECT STORE in a later operand: refused before, now read again too.
round_trips('our $n = 1; sub f { return $n . ($n = 5) } print f(), " $n\n";',   'a store, in a sub');
round_trips('our $n = 1; print $n . ($n = 5), "\n";',                            'a store, at top level');
round_trips('our $n = 1; print $n, $n++, "\n";',                                 'a post-increment in a list');

# A COPY is not an alias: what it read stands.
round_trips($f . 'print f(1), "$g", f(0), $g; print "\n";',                      'a stringified copy');
round_trips($f . 'my $v = $g; print $v, f(1), $g, "\n";',                        'a copy made before');
round_trips('our $g = 1; sub f { 0 } print $g, f(), "\n";',                      'a call that does not write it');

done_testing;
