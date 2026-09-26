# ABOUTME: `$o->$m` takes its method name from a scalar at runtime; the name
# ABOUTME: is an OPERAND of the `method` op, not a constant on it.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# TWO OPS, AND ONLY ONE WAS HANDLED. perl has `method_named` for a literal
# method name and `method` for one computed at runtime -- measured:
#
#     $o->hi      method_named[hi]
#     $o->$m      padsv[$o] / padsv[$m] / method lK/1
#
# The NAME IS AN OPERAND of `method`, pushed beside the invocant, where
# `method_named` carries it as a constant on the op. _handle_method_named reads
# `$op->meth_sv`, which a dynamic `method` does not have, so the name came out
# empty and OpMap's `method => [1, undef, 1, 0]` popped only one value.
#
# The result was a SILENT MISCOMPILE, not a refusal:
#
#     Call dispatch_kind=indirect name= in=[PadAccess]
#
# emitted as `$o->()` -- the method name dropped entirely -- which dies with
# "Can't use an undefined value as a subroutine reference". Found by diffing
# our round trip against pvm's ratchet: their parser handles this and ours
# built a graph that lies.

round_trips( <<'SRC', 'a method name held in a scalar' );
package Foo;
sub hi { return "hi" }
package main;
my $o = bless {}, "Foo";
my $m = "hi";
print $o->$m, "\n";
SRC

round_trips( <<'SRC', 'the name chosen at runtime' );
package Foo;
sub one { return "1" }
sub two { return "2" }
package main;
my $o = bless {}, "Foo";
for my $m ("one", "two") {
    print $o->$m;
}
print "\n";
SRC

# A LITERAL METHOD NAME MUST BE UNDISTURBED -- it takes the other op and is the
# regression guard for anything done to this one.
round_trips( <<'SRC', 'a literal method name still works' );
package Foo;
sub hi { return "hi" }
package main;
my $o = bless {}, "Foo";
print $o->hi, "\n";
SRC

done_testing;
