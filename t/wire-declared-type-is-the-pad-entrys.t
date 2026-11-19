# ABOUTME: A `my @a` or `my %h` is typed Array or Hash from its pad entry's sigil;
# ABOUTME: no use site can make the container a Scalar or a Str.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# THE DEFECT (docs/plans/2026-11-19-sigil-stamp-investigation.md, section 1).
# B::SoN::_declared_slot_type answered `Scalar` for every PadAccess and never
# read the sigil. Backward inference then met that with what a use required:
# `!@a` requires a List (Count's operand), meet(Scalar, List) is Scalar, and
# the one shared `@a` node was stamped Scalar -- so `\@a` was a ScalarRef.
# `my %h; my $n = %h; print "n=$n"` stamped the hash Str.
#
# A declaration is the pad entry: `@` holds an Array, `%` a Hash, whatever
# reads it. Nothing sits below Array or Hash in the lattice, so the
# declaration is the answer and no use narrows it.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub nodes ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return [] unless length $json;
    return JSON::PP->new->utf8->decode($json)->{methods}{'main::__PROGRAM__'}{nodes};
}

sub pad ( $ns, $sigil, $symbol ) {
    grep { $_->{op} eq 'PadAccess' && $_->{fields}{sigil} eq $sigil && $_->{fields}{symbol} eq $symbol } @$ns;
}

subtest 'an array counted and referenced is an Array, its reference an ArrayRef' => sub {
    my $ns = nodes('my @a; print "e\n" if !@a; my $r = \@a; push @$r, 1; print scalar(@a), "\n";');
    my ($a) = pad( $ns, '@', 'a' ) or return fail 'no PadAccess @a';
    is $a->{stamp}, 'Array', '@a is an Array';
    my ($ref) = grep { $_->{op} eq 'Ref' && $_->{inputs}[0] == $a->{id} } @$ns;
    is $ref->{stamp}, 'ArrayRef', '\@a is an ArrayRef' if ok $ref, 'a Ref of it';
};

subtest 'a hash read as a string is still a Hash' => sub {
    my $ns = nodes('my %h; my $n = %h; print "n=$n\n";');
    my ($h) = pad( $ns, '%', 'h' ) or return fail 'no PadAccess %h';
    is $h->{stamp}, 'Hash', '%h is a Hash';
};

subtest 'an aggregate nothing requires anything of is typed too' => sub {
    my $ns = nodes('my @u; push @u, 1; my %v; $v{a} = 1; print "ok\n";');
    my ($u) = pad( $ns, '@', 'u' ) or return fail 'no PadAccess @u';
    my ($v) = pad( $ns, '%', 'v' ) or return fail 'no PadAccess %v';
    is $u->{stamp}, 'Array', '@u is an Array';
    is $v->{stamp}, 'Hash',  '%v is a Hash';
};

# A CELL HOLDS THE VARIABLE, WHATEVER ITS SIGIL. MakeCell's operand row said
# Scalar, which no one noticed while a captured `@a` was stamped Scalar or
# nothing; typed Array, the coercion pass put Coerce(Array -> Scalar) between
# the array and its cell, and the cell was of a count.
subtest 'a captured array goes into its cell as itself' => sub {
    my $ns = nodes('my @a = (1); my $f = sub { push @a, 2 }; $f->(); print scalar(@a), "\n";');
    my %by = map { $_->{id} => $_ } @$ns;
    my ($cell) = grep { $_->{op} eq 'MakeCell' } @$ns or return fail 'no MakeCell';
    isnt $by{ $cell->{inputs}[0] }{op}, 'Coerce', 'no Coerce between the array and its cell';
};

subtest 'a scalar slot is still narrowed by its uses' => sub {
    my $ns = nodes('sub add1 { my ($x) = @_; $x + 1 } print add1(2), "\n";');
    ok 1, 'translates';
};

done_testing;
