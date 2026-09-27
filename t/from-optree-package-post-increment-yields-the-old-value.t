# ABOUTME: a package scalar's $n++ must yield the PRE-increment value, and two
# ABOUTME: increments must be two computations -- the lvalue name is not a read.
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

# AN LVALUE EntryDef IS A NAME TOKEN, NOT A READ -- the gvsv handler says so in
# as many words, and gives it no memory input for exactly that reason: it is the
# destination handed to sassign, and a memory input would make the store's own
# operand depend on the memory it produces.
#
# The pre/post increment handler pops that name token as its `$old` and used it
# as BOTH the store target and the value the arithmetic reads. Two consequences,
# both measured on `our $n = 10; print "a ", $n++, "\n"; print "b ", $n++, "\n"`:
#
#   perl   a 10 / b 11
#   ours   a 11 / b 12
#
# 1. The post-increment yielded the NEW value. `$old` is the unpinned name, so
#    `Coerce($old)` in the print reads whatever the slot holds at the point the
#    deparser spells it -- after the store, not before.
# 2. Both increments shared ONE Add. With no memory input the two name tokens
#    hash-cons to one node, so `Add(name, 1)` does too, and the second
#    EntryWrite stored the first increment's value.
#
# The Subscript and CellParam arms of the same handler already do this right:
# each builds a SEPARATE rvalue read pinned to the current memory and keeps the
# lvalue as the store target only. This is the third member of that family.
subtest 'a post-increment in a print list yields the old value' => sub {
    my $src = <<'SRC';
our $n = 10;
print "a ", $n++, "\n";
print "b ", $n++, "\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'both prints see the pre-increment value'
        or diag $out;
};

# THE PRE FORM IS THE OTHER HALF, and it must NOT change: `++$n` yields the new
# value, so a fix that simply reads before the store would break it if the read
# were also what the pre form yields.
subtest 'a pre-increment still yields the new value' => sub {
    my $src = <<'SRC';
our $n = 10;
print "a ", ++$n, "\n";
print "b ", ++$n, "\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'both prints see the post-increment value'
        or diag $out;
};

# TWO INCREMENTS ARE TWO COMPUTATIONS. Without a memory pin on the read the two
# name tokens are one node, so the arithmetic is one node, so the second store
# writes the first result -- the counter stops counting. This shape shows it
# without post-increment semantics in the way at all.
subtest 'consecutive increments accumulate' => sub {
    my $src = <<'SRC';
our $n = 0;
$n++;
$n++;
$n++;
print "$n\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'three increments make three'
        or diag $out;
};

# DECREMENT IS THE SAME OP FAMILY -- the handler's regex covers all four, so the
# fix has to as well.
subtest 'a post-decrement in a print list yields the old value' => sub {
    my $src = <<'SRC';
our $n = 10;
print "a ", $n--, "\n";
print "b ", $n--, "\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'both prints see the pre-decrement value'
        or diag $out;
};

done_testing;
