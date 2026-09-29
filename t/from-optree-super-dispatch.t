# ABOUTME: `$o->SUPER::hi()` dispatches from the ENCLOSING package's @ISA, not
# ABOUTME: from the invocant's class -- a different lookup, not a plain method.
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

# A THIRD METHOD OP, AND IT CARRIES ITS NAME. Measured:
#
#     $o->hi            method_named[PV "hi"]
#     $o->$m            method  (the name is an OPERAND -- fixed separately)
#     $o->SUPER::hi()   method_super[PV "hi"]
#
# So `method_super` is shaped like `method_named` -- a constant name on the op --
# and differs in WHERE IT LOOKS: not the invocant's class but the @ISA of the
# package the call is written in. That is why it cannot simply be treated as a
# named method: the same source with the same invocant resolves differently.
#
# It sat in %CONSUMED_BY_OPENER in t/every-op-has-a-disposition.t on the
# assumption entersub consumed it, which is the assumption that hid the
# dynamic-method defect. Here it produced a Call naming `unknown`, so the
# deparser refused -- honest, but a refusal rather than a lowering.

# ATTEMPTED AND REVERTED 2026-09-26. A `super_method` dispatch kind and a
# `->SUPER::name()` spelling are both correct and both insufficient, because
# THE WIRE DOES NOT RECORD WHICH PACKAGE THE CALL WAS WRITTEN IN.
#
# SUPER:: resolves through the @ISA of the ENCLOSING package. The graph for
# `package Derived; ... $o->SUPER::hi()` is
#
#     Call in=[4] dispatch_kind=super_method name=hi
#
# with `Derived` nowhere, and the emission puts every statement in `main`, so
# the emitted `->SUPER::hi()` looked up main's @ISA and died "Can't locate
# object method via package main".
#
# So this needs the enclosing package, and it lands on the wire now, in the
# method name: `$o->Derived::SUPER::hi()`, which perl resolves from Derived
# wherever it is written. The package is the enclosing statement's (its
# nextstate), since method_super's rclass is 0. Added producer-side ahead of
# chalk, as approved 2026-09-28; no longer TODO.
round_trips( <<'SRC', 'SUPER:: reaches the parent method' );
package Base;
sub hi { return "base" }
package Derived;
our @ISA = ("Base");
my $o = bless {}, "Derived";
print $o->SUPER::hi(), "\n";
SRC

# THE DISTINCTION IS OBSERVABLE: when the child OVERRIDES the method, a plain
# call reaches the child and SUPER:: reaches the parent. A lowering that treated
# SUPER:: as an ordinary named dispatch would print the child's answer twice.
round_trips( <<'SRC', 'SUPER:: skips an override' );
package Base;
sub hi { return "base" }
package Derived;
our @ISA = ("Base");
sub hi { return "derived" }
sub both { my $s = shift; return $s->SUPER::hi() . "/" . $s->hi() }
package main;
my $o = bless {}, "Derived";
print $o->both(), "\n";
SRC

done_testing;
