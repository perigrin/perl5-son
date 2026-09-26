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

# TODO UNTIL ALL THREE PARTS LAND. The subject change alone makes this compile
# and print the WRONG ANSWER (`$tr` undeclared), so it is not shippable on its
# own -- see docs/plans/2026-09-26-a-destructive-tr-on-a-lexical.md. Marked TODO
# rather than deleted: it is the acceptance test for that plan, and it must fail
# for the reason it names until the declaration and the double-run are fixed too.
subtest 'the count form names the variable' => sub {
    my $src = <<'SRC';
my $tr = "a.c";
my $cnt = ($tr =~ tr/./Z/);
print "$tr $cnt\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };

    # EACH ASSERTION CARRIES ITS OWN TODO, not the subtest. A `todo` around the
    # whole block amnesties the failures and the subtest then PASSES, so the
    # harness reports "TODO passed" -- which says the work is done when it is
    # not. Marked here so each one fails visibly, under amnesty, naming what it
    # is waiting for.
    my $todo = todo 'the declaration and the single-run are not fixed yet';

    like $out, qr/\$\w+ =~ tr\[/,
        'the tr subject is a variable, not a value';

    my $f = write_tmp( $out, 'c' );
    my $chk = qx($^X -c $f 2>&1);
    unlink $f;
    like $chk, qr/syntax OK/, 'the emission compiles';

    is runs($out), runs($src), 'and it prints what perl prints';
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
