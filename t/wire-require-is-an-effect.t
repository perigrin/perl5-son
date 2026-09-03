# ABOUTME: `require` is a memory effect, not a pure value -- it must not be DCE'd.
# ABOUTME: `use X` is BEGIN { require X; X->import }, so only the runtime half lowers.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return ($w, $err);
}

sub nodes_of ($w, $meth) {
    return [ map { { $_->%*, ($_->{fields} // {})->%* } }
             ($w->{methods}{$meth} ? $w->{methods}{$meth}{nodes}->@* : ()) ];
}

# `require` IS A MEMORY EFFECT, NOT A VALUE. Measured on 5.42.0:
#
#     my $r = require POSIX;   POSIX::SigRt=HASH(...)   the module's last value
#     my $r = require POSIX;   1                        already loaded
#
# so the result is NOT a function of the inputs -- it depends on whether the
# module was loaded, which is global state. It mutates %INC and the symbol
# table, and a later `Foo->new` depends on it through that state with no data
# edge to say so. That is exactly what the memory chain expresses.
#
# It was SILENTLY DROPPED: the generic-Call path threads control only when
# OPf_WANT_VOID, and perl compiles `require Foo;` as want=SCALAR. `print`
# escaped that only because it has its own node type. The graph emitted
# `Foo->new` with the load that makes it valid deleted.
subtest 'a bareword require survives as a call' => sub {
    my ($w, $err) = wire('require POSIX; print 1;', 'req-bare');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    my ($req) = grep { ($_->{op} eq 'Call') && (($_->{name} // '') eq 'require') }
                $prog->@*;
    ok $req, 'the require is in the graph at all';
};

# A DYNAMIC require ALREADY WORKED, and must keep working -- it is the same op,
# so a fix keyed on the operand rather than the op would have missed one of them.
subtest 'a dynamic require survives too' => sub {
    my ($w, $err) = wire('my $m = "POSIX"; eval { require $m }; print 1;', 'req-dyn');
    unlike $err, qr/INTERNAL/, 'no internal error' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    ok scalar(grep { $_->{op} eq 'Call' } $prog->@*),
        'a Call is present for the dynamic form';
};

# ORDER AGAINST THE IMPORT IS LOAD-BEARING. `use X LIST` is exactly
# BEGIN { require X; X->import(LIST) } -- verified: the two compile to
# byte-identical exec chains. In the RUNTIME spelling both ops are in the
# graph, and `import` must not float above the `require`: calling
# POSIX->import before POSIX is loaded is a different program. Only a shared
# chain expresses that, which is why require goes on memory and not merely on
# control.
subtest 'require is ordered before the import that needs it' => sub {
    my ($w, $err) = wire(
        'require POSIX; POSIX->import(); print 1;', 'req-import');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');

    my ($req) = grep { ($_->{op} eq 'Call') && (($_->{name} // '') eq 'require') }
                $prog->@*;
    my ($imp) = grep { ($_->{op} eq 'Call') && (($_->{name} // '') eq 'import') }
                $prog->@*;
    ok $req && $imp, 'both the require and the import are present' or return;
    cmp_ok $req->{id}, '<', $imp->{id},
        '... and the require is built first';
};

# NOT HASH-CONSED. Two `require POSIX` are two DIFFERENT events -- measured
# above, the first yields a hash and the second yields 1. Collapsing them to
# one node would claim the program loads the module once when it asks twice,
# which is the same defect ArrayLiteral and MakeCell avoid by per-occurrence
# identity.
subtest 'two requires of one module stay two nodes' => sub {
    my ($w, $err) = wire('require POSIX; require POSIX; print 1;', 'req-twice');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    my @req = grep { ($_->{op} eq 'Call') && (($_->{name} // '') eq 'require') }
              $prog->@*;
    is scalar(@req), 2, 'both requires survive as distinct nodes';
};

# `use` NEEDS NO NODE AND CANNOT HAVE ONE. It is the same two ops wrapped in
# BEGIN, so it has already run before B::SoN is invoked and leaves NOTHING in
# the optree -- measured, `use POSIX qw(floor); 1` and its BEGIN{} equivalent
# both compile to `nextstate const lineseq leavesub`. Nothing is being dropped
# here; there is nothing to drop.
subtest 'a use leaves no runtime op to lower' => sub {
    my ($w, $err) = wire('use POSIX (); print 1;', 'use-none');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    is scalar(grep { ($_->{name} // '') eq 'require' } $prog->@*), 0,
        'no require node -- the use ran at compile time';
    ok scalar(grep { $_->{op} eq 'Print' } $prog->@*),
        '... and the rest of the program is intact';
};

done_testing;
