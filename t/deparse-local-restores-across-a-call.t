# ABOUTME: `local` must restore at scope exit even when the localised value is
# ABOUTME: only ever read through a CALL, where the read is not lexically visible.
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

sub runs ($src) {
    my $f = write_tmp( $src, 'r' );
    my $o = qx($^X $f 2>&1);
    unlink $f;
    return $o;
}

sub emit ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    my $data = eval { JSON::PP->new->decode($j) };
    return ( undef, $e ) unless $data && $data->{methods}{'main::__PROGRAM__'};
    my $out = eval { SoN::Deparse->new->render($data) };
    return ( undef, ( $@ || 'refused' ) ) unless defined $out;
    return ( $out, undef );
}

# LOCAL IS A SAVE AND A RESTORE, and the restore is the half that goes missing.
# Measured -- the SAME construct, read two ways:
#
#     our $g = 1; { local $g = $g + 10; print $g } print $g
#       perl 11 1    ours 11 1      read in the SAME scope: correct
#
#     our $v = "outer";
#     sub show { print $v } sub inner { local $v = "inner"; show() }
#       perl inner outer    ours inner inner
#
# The emission drops `local` entirely:
#
#     sub inner { $main::v = "inner"; my $eff5 = show(); }
#
# so the outer value is CLOBBERED PERMANENTLY rather than restored. It compiles,
# runs, exits 0, and prints a plausible wrong answer.
#
# WHY THE SAME-SCOPE CASE PASSES: the read is lexically visible, so the walk
# sees the pre-local value and the post-scope value as two SSA bindings and
# emits neither a save nor a restore -- which happens to print the right thing.
# Across a call there is no such binding: the callee reads the package variable
# at whatever value it holds, and only a real restore can put the old one back.
# The corpus covers `local` only in the same-scope shape
# (adjacency-05_scoping.md), which is why no census caught this.

subtest 'local read through a call restores at scope exit' => sub {
    my $src = <<'SRC';
our $v = "outer";
sub show { print "$v\n" }
sub inner { local $v = "inner"; show() }
inner();
show();
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };

    is runs($out), runs($src), 'the outer value comes back' or diag $out;
};

# A LOCALISED GLOB IS THE SAME DEFECT, and it is the shape perl's own t/ uses
# (comp/fold.t:105 `local *_`, comp/proto.t:674).
subtest 'a localised glob restores too' => sub {
    my $src = <<'SRC';
our $v = "outer";
sub show { print "$v\n" }
sub inner { local *v = \"inner"; show() }
inner();
show();
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };

    # THE SAVED THING IS THE SLOT REFERENCE, which three measurements settle:
    #
    #   my $s = $v;  ... $v = $s     Modification of a read-only value --
    #                                the slot now points at the literal
    #   my $s = *v;  ... *v = $s     inner inner -- a glob is a NAME, so
    #                                copying it snapshots nothing
    #   my $s = \$v; ... *v = $s     inner outer -- correct
    #
    # So the restore is a glob BIND to a ref of the saved value, not a scalar
    # store. `local $v` differs because it changes a value in place rather than
    # rebinding a slot, which is why saving the value is right there and wrong
    # here -- the same construct, two mechanisms.
    is runs($out), runs($src), 'the outer value comes back' or diag $out;
};

# THE SAME-SCOPE SHAPE MUST NOT REGRESS. It round-trips today, and it is the
# only shape the corpus exercises -- so a fix that emitted a restore in the
# wrong place would break the case that currently works and nothing would say
# so except this.
subtest 'local read in the same scope still round-trips' => sub {
    my $src = <<'SRC';
our $g = 1;
{
  local $g = $g + 10;
  print "$g\n";
}
print "$g\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'the inner and outer values are both right'
        or diag $out;
};

done_testing;
