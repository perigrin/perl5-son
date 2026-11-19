#!/usr/bin/perl
# gen_corpus.pl -- write every pvm corpus case to corpus/NNN.pl (+ .want) and its B::SoN wire to corpus/NNN.json
use v5.42.0;
use lib '/home/user/repo/tools/lib';
use PvmCorpus qw(read_cases);
my @cases = read_cases('/home/user/repo/t/corpus/mdtest/pvm');
my $d = '/tmp/claude-0/audit/corpus';
my $i = 0;
for my $c (@cases) {
    my $id = sprintf '%03d', ++$i;
    open my $o, '>', "$d/$id.pl" or die; print $o $c->{src}; close $o;
    open $o, '>', "$d/$id.want" or die; print $o $c->{want}; close $o;
    open $o, '>', "$d/$id.file" or die; print $o $c->{file}; close $o;
    system("ulimit -v 4000000; timeout 120 perl -I/home/user/repo/lib -MO=-q,SoN,json,not_package=SoN $d/$id.pl > $d/$id.json 2> $d/$id.err");
}
say "done $i";
