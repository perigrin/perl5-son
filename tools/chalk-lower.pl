#!/usr/bin/perl
# ABOUTME: Lower one B::SoN wire JSON's program graph to LLVM IR through chalk's
# ABOUTME: pipeline; a worker for corpus-llvm-roundtrip.pl, run with chalk's lib on @INC.
#
#   perl -I$CHALK/lib -I$CHALK/t/lib tools/chalk-lower.pl IN.json OUT.ll
#
# Exit 0 with OUT.ll written, or print one line -- `LOAD: why` or `GAP: why`
# -- and exit 1. The same seam chalk's own son-e2e.t drives
# (Chalk::CodeGen::Pipeline::run_detail, program mode), selecting the
# program's top level rather than a wrapped expression: a corpus case is a
# whole program that prints.
use v5.42.0;
use Chalk::CodeGen::Pipeline;

my ($in, $outf) = @ARGV;
my $json = do { local (@ARGV, $/) = $in; <> };
my $select = sub ($graphs, $mop) {
    my $g = $graphs->{'main::__PROGRAM__'} or return ();
    my $ret = $g->returns->[0] or return ();
    return ([ 'main::__PROGRAM__', $ret ]);
};
my ($units, $graphs, undef, $err) = eval {
    Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
};
$err //= $@ if $@;
sub one_line ($s) { $s =~ s/\s+at \S+ line \d+\.?\s*\z//; $s =~ s/\s+/ /g; $s =~ s/^(?:GAP:\s*)+//; $s }
if ($err) { say 'LOAD: ', one_line($err); exit 1 }
unless (@$units) { say 'LOAD: no program graph with a return'; exit 1 }
my $u = $units->[0];
unless ($u->{ok}) { say 'GAP: ', one_line($u->{err} // 'lowering failed'); exit 1 }
open my $o, '>', $outf or die "$outf: $!";
print $o $u->{ll};
close $o;
exit 0;
