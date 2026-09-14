# ABOUTME: A method call's invocant is input 0, not the class_name field.
# ABOUTME: `$o->m` and `Thing->m` differ in what the method receives, not just in spelling.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
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

# THE INVOCANT IS INPUT 0, AND class_name IS NOT IT. Measured on
# `my $o = Thing->new; $o->greet("bob"); Thing->greet("amy")`:
#
#      4 Call name=new   class=Thing  in=[]
#      6 Call name=greet class=Thing  in=[Call(4), Constant "bob"]
#     10 Call name=greet class=Thing  in=[Constant "Thing", Constant "amy"]
#
# BOTH carry class_name=Thing -- it is where the method was RESOLVED, not who
# it is called on. Input 0 is the invocant: `Call(4)` for the instance call
# and the class name itself for the class call.
#
# Rendering `class_name->name(ALL inputs)` therefore did two wrong things at
# once: `$o->name` became `Thing->name($o)`, calling the method on the CLASS
# and passing the instance as an argument, and `Thing->new("inst")` became
# `Thing->new("Thing", "inst")`, passing the class twice.
#
# A METHOD THAT BEHAVES DIFFERENTLY PER INVOCANT is the only way to see it: a
# method ignoring its invocant returns the same thing either way.
#
# CHECKED ON THE GRAPH, NOT BY ROUND-TRIPPING. `-MO=SoN,package=main`
# deliberately emits ONE package, so a multi-package program's other subs are
# not on the wire and the emitted program cannot define them. That is a
# harness limitation, not a defect, and it makes the round trip unavailable
# for exactly the programs method dispatch needs.
subtest 'the invocant is input 0' => sub {
    my $data = graph_of(<<'SRC');
package Thing;
sub new  { my ($c, $n) = @_; return bless { n => $n }, $c }
sub name { my $s = shift; return ref($s) ? $s->{n} : "CLASS" }
package main;
my $o = Thing->new("inst");
print $o->name, "\n";
print Thing->name, "\n";
SRC
    ok $data && $data->{methods}{'main::__PROGRAM__'}, 'it translates'
        or return;

    my @ns = ($data->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    my %by = map { $_->{id} => $_ } @ns;
    my @m = sort { $a->{id} <=> $b->{id} }
            grep { ($_->{op} // '') eq 'Call'
                && ((($_->{fields} // {})->{dispatch_kind} // '') eq 'method') }
            @ns;
    ok scalar(@m) >= 3, 'three method calls' or return;

    # BOTH CARRY class_name, which is why it cannot be the invocant: it
    # records where the method was RESOLVED.
    is +(($m[1]{fields} // {})->{class_name}), 'Thing',
        'the instance call carries class_name too';

    # THE INSTANCE CALL'S INPUT 0 IS THE OBJECT, not the class name.
    my $inv = $by{ ($m[1]{inputs} // [])->[0] // -1 };
    is $inv->{op}, 'Call', 'its input 0 is the constructor result';

    # THE CLASS CALL'S INPUT 0 IS THE CLASS NAME.
    my $cinv = $by{ ($m[2]{inputs} // [])->[0] // -1 };
    is +(($cinv->{fields} // {})->{value}), 'Thing',
        'the class call names the class as its invocant';

    # AND RENDERING USES THAT, not class_name -- so the two spell
    # differently even though their class_name is identical.
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    ok defined $out, 'it renders' or do {
        diag(($d->gap // '?') =~ s/\n.*//sr); return;
    };
    like $out, qr/->name\(\)/, 'the method is called on its invocant';
    unlike $out, qr/name\(\$\w+\)/,
        'and the invocant is NOT passed as an argument';
};

# AN INVOCANT IN A VARIABLE has no class_name at all, which is the shape
# comp/opsubs.t holds -- `$obj->can($m)`, the class not known statically.
# It needs no special case once the invocant is read from input 0.
subtest 'an invocant the graph cannot name' => sub {
    my $data = graph_of(<<'SRC');
package Thing;
sub new { return bless {}, shift }
sub hi  { return "hi" }
package main;
my $o = Thing->new;
my $m = "hi";
print $o->can($m) ? "can\n" : "cannot\n";
SRC
    ok $data && $data->{methods}{'main::__PROGRAM__'}, 'it translates'
        or return;

    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    ok defined $out, 'it renders'
        or diag(($d->gap // '?') =~ s/\n.*//sr);
    like $out, qr/->can\(/, 'the runtime method name is called on the invocant'
        if defined $out;
};

# A SUB NAMED AFTER AN OPERATOR NEEDS THE AMPERSAND. comp/opsubs.t defines
# subs called `s`, `tr`, `y`, `q` and friends, and `s("main")` parses as the
# SUBSTITUTION OPERATOR -- measured, "syntax error ... near \"my \"" where the
# emitted line was `my $eff114 = s("main");`.
#
# The parens are not optional either: `&s` without them passes the CALLER's
# @_, which is a different call.
subtest 'a sub named after an operator' => sub {
    # THE SOURCE MUST USE `&` TOO -- `s("a")` does not compile even in the
    # original, which is why comp/opsubs.t writes its calls this way.
    round_trips(<<'SRC', 'subs called s and tr');
sub s  { return "s-" . shift }
sub tr { return "tr-" . shift }
print &s("a"), "\n";
print &tr("b"), "\n";
SRC

    round_trips(<<'SRC', 'an ordinary name still calls plainly');
sub plain { return "p-" . shift }
print plain("c"), "\n";
SRC
};

done_testing;
