# ABOUTME: Loaded before -MO=SoN, it reports, for each loop B::SoN walks, what the pre-scan said and
# ABOUTME: what the walk found: the iterator's write (`ITER`) and the slots the body rebinds (`SLOTS`).
package ScanAgree;
use v5.42.0;
use B ();
use Scalar::Util ();
use SoN::FromOptree;

# THE PRE-SCAN IS A SECOND ANALYSIS (audit 2, section 3, Braun): the header
# decides from the ops what the body will write, and the walk then builds on
# it. Each answer the walk finds and the scan did not is refused by name where
# it is found (_check_writes, _braun_seal); t/pre-scan-agrees-with-the-walk.t
# holds the two equal over the corpus and the probes, both ways.
my $where = sub {
    my $cv = $SoN::FromOptree::OPS_CV;
    return eval { my $gv = $cv->GV; $gv->STASH->NAME . '::' . $gv->NAME } // '?';
};
no warnings 'redefine';
{
    my $orig = \&SoN::FromOptree::_check_writes;
    *SoN::FromOptree::_check_writes = sub {
        my ( $key, $scanned, $wrote ) = @_;
        printf STDERR "ITER %s %s scan=%d walk=%d\n", $where->(), $key, $scanned ? 1 : 0, $wrote ? 1 : 0;
        goto &$orig;
    };
}
{
    my $orig = \&SoN::FromOptree::_braun_seal;
    *SoN::FromOptree::_braun_seal = sub {
        my ( $sim, $phis, $pre_scope, @skip ) = @_;
        my %skip = map { $_ => 1 } @skip;
        my $post = $sim->scope_bindings;
        my ( @missed, @extra );
        for my $k ( sort keys %$pre_scope ) {
            next if $skip{$k} || SoN::FromOptree::_key_lives_in_memory($k);
            next unless defined $post->{$k} && defined $pre_scope->{$k};
            my $b = $post->{$k}->resolved;
            if ( $phis->{$k} ) {
                # (a Phi the walk never rebound from: the scan said written, the walk did not)
                push @extra, $k if $b == $phis->{$k} || $b == $pre_scope->{$k}->resolved;
            }
            elsif ( $b != $pre_scope->{$k}->resolved ) { push @missed, $k }
        }
        printf STDERR "SLOTS %s missed=%s extra=%s\n", $where->(), join( ',', @missed ) || '-', join( ',', @extra ) || '-';
        goto &$orig;
    };
}

1;
