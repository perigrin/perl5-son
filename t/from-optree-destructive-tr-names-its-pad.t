# ABOUTME: a destructive tr/// on a lexical must name the PAD SLOT, because perl
# ABOUTME: refuses to transliterate a value and the trans op carries that targ.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub write_tmp ($src, $tag) {
    my $f = "$dir/$tag." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub graph_of ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    return eval { JSON::PP->new->decode($j) };
}

sub emit ($src) {
    my $data = graph_of($src) or return ( undef, 'no graph' );
    return ( undef, 'no program' ) unless $data->{methods}{'main::__PROGRAM__'};
    my $out = eval { SoN::Deparse->new->render($data) };
    return ( undef, ( $@ || 'refused' ) ) unless defined $out;
    return ( $out, undef );
}

sub runs ($src) {
    my $f = write_tmp( $src, 'r' );
    my $o = qx($^X $f 2>&1);
    unlink $f;
    return $o;
}

# PERL REFUSES A VALUE HERE. Measured:
#
#     "a.c" =~ tr/./Z/    Can't modify constant item in transliteration (tr///)
#     $tr   =~ tr/./Z/    compiles
#
# and the destructive form is the only one that returns a count, so the count
# form CANNOT be rendered with /r to dodge the lvalue. The subject has to be a
# variable.
#
# THE OP NAMES THE SLOT ITSELF. A `tr` on a lexical compiles to a PVOP carrying
# the targ and NO padsv operand at all -- measured:
#
#     my $tr = "a.c"; $tr =~ tr/./Z/
#       7  <"> trans[$tr:1,3] sP/TRANS=ONLY_UTF8_INVARIANTS
#
# so the subject is not on the stack for this op to pop. What `pop_node` returns
# is the value the slot was BOUND to, left there by the preceding assignment,
# and building the node over it is what emitted `("a.c" =~ tr[.][Z])`.
#
# The package-scalar form already gets this right -- its subject is the EntryDef
# -- which is why only the lexical shape failed. Case 010 of pvm's conformance
# corpus is this, and its emission did not compile.

# THE SUBJECT ALONE IS NOT THE FIX, and this subtest is why the other four
# exist. Giving the tr/// its pad slot makes this COMPILE and print the wrong
# answer -- `$tr` pruned and undeclared, so it printed ` 1` for perl's `aZc 1`.
# A compile error traded for a silent wrong answer is the worse of the two.
#
# Four parts, all of them load-bearing: the slot is DEMOTED (so its store is a
# real Assign and the declaration survives), the tr/// READS that slot, it is
# PINNED to the control chain (so the mutation lands where it happens), and it
# is emitted ONCE (so the count does not re-run it). See
# docs/plans/2026-09-26-a-destructive-subst-on-a-lexical.md.
subtest 'the count form names the variable' => sub {
    my $src = <<'SRC';
my $tr = "a.c";
my $cnt = ($tr =~ tr/./Z/);
print "$tr $cnt\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };

    like $out, qr/\$\w+ =~ tr\[/,
        'the tr subject is a variable, not a value';

    my $f = write_tmp( $out, 'c' );
    my $chk = qx($^X -c $f 2>&1);
    unlink $f;
    like $chk, qr/syntax OK/, 'the emission compiles';

    is runs($out), runs($src), 'and it prints what perl prints';
};

# THE MUTATION IS AN ORDERING FACT, and this is the case that proves it. A read
# BETWEEN the tr/// and the use of its count must see the transliterated string:
#
#     my $t = "a.c"; my $c = ($t =~ tr/./Z/);
#     print "mid $t\n"; print "end $c\n";
#       perl  mid aZc / end 1
#
# Unpinned from the control chain, the deparser emitted the tr/// wherever its
# value was first READ -- the second print -- and the first printed `mid a.c`.
# Silent, and a wrong answer rather than a refusal.
subtest 'a read between the tr and its count sees the mutation' => sub {
    my $src = <<'SRC';
my $t = "a.c";
my $c = ($t =~ tr/./Z/);
print "mid $t\n";
print "end $c\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'both statements see the right value'
        or diag $out;
};

# THE SAME DEFECT IS s///'s, and the fix is shared -- so the guard is too. This
# shape REFUSED before (the counted s/// had no lvalue, because a pad has no
# EntryWrite to recover the name from), which is why it never showed up as a
# wrong answer the way tr/// did.
subtest 'a counted s/// on a lexical round-trips' => sub {
    my $src = <<'SRC';
my $s = "aaa";
my $n = ($s =~ s/a/b/g);
print "$s $n\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'the subject and the count are both right'
        or diag $out;
};

# THE /r FORM IS NOT AFFECTED and must not become an lvalue: it yields a new
# string and leaves the subject alone, so a value subject is correct there.
subtest 'the /r form still takes a value' => sub {
    my $src = <<'SRC';
my $tr = "a.c";
my $new = ($tr =~ tr/./Z/r);
print "$tr $new\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'round-trips' or diag $out;
};

# A PACKAGE SCALAR ALREADY WORKED, and is the regression guard: its subject is
# an EntryDef and must stay one.
subtest 'a package scalar keeps its EntryDef subject' => sub {
    my $src = <<'SRC';
our $tr = "a.c";
my $cnt = ($tr =~ tr/./Z/);
print "$tr $cnt\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'round-trips' or diag $out;
};

done_testing;
