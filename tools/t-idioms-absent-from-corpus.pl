#!/usr/bin/perl
# ABOUTME: Which idioms appear in perl's t/ and in NO corpus perl block --
# ABOUTME: obligation 3 of the round-trip goal, as a measurement not a guess.
#
# SEARCHES BLOCK CONTENTS, NOT FILES. A construct named in a topic's PROSE is
# not a case that exercises it, and `grep -l` over the .md files counts both.
# pvm hit the same shape counting `parses: no` with grep and got 5 where the
# answer was 3.
#
# THE OUTPUT IS A CANDIDATE LIST, NOT A VERDICT. An idiom absent from the corpus
# is worth PROPOSING; whether it belongs, and in which tier, is pvm's call and
# their op-budget lint decides it. Send the op set with each case
# (`-MO=Concise,-exec`) so that decision is cheap.
#
#   perl tools/t-idioms-absent-from-corpus.pl
#   SON_CORPUS=... SON_PERL_T=... perl tools/t-idioms-absent-from-corpus.pl
use strict;
use warnings;
use FindBin;

my $CORPUS = $ENV{SON_CORPUS}
          // "$FindBin::Bin/../t/corpus/mdtest/pvm";
my $PERL_T = $ENV{SON_PERL_T} // "$ENV{HOME}/dev/perl5/t";
die "no corpus at $CORPUS (set SON_CORPUS)\n" unless -d $CORPUS;
die "no perl t/ at $PERL_T (set SON_PERL_T)\n" unless -d $PERL_T;

# The idioms to ask about, each with the pattern that recognises it. Kept as an
# explicit list rather than derived: "what counts as an idiom" is a judgement,
# and a derived list would silently change meaning as either corpus moved.
my @IDIOMS = (
    [ 'glob bind      *NAME = \\...'  => qr{^\s*\*[A-Za-z_]\w*\s*=\s*\\} ],
    [ 'glob bind      *NAME = *NAME'  => qr{^\s*\*[A-Za-z_]\w*\s*=\s*\*}  ],
    [ 'undef *NAME'                   => qr{\bundef\s+\*}                 ],
    [ 'continue { }'                  => qr{\bcontinue\s*\{}              ],
    [ 'wantarray ? ... : ...'         => qr{\bwantarray\s*\?}             ],
    [ 'format / write'                => qr{^\s*(?:format\s+\w+\s*=|write\b)} ],
    [ 'goto &NAME'                    => qr{\bgoto\s+&}                   ],
    [ 'local *NAME'                   => qr{\blocal\s+\*}                 ],
);

# Perl blocks only, from the corpus markdown.
my @corpus_lines;
for my $md ( sort glob "$CORPUS/*.md" ) {
    open my $fh, '<', $md or die "$md: $!";
    my $in = 0;
    while ( my $l = <$fh> ) {
        if    ( $l =~ /^```perl\s*$/ ) { $in = 1; next }
        elsif ( $in && $l =~ /^```\s*$/ ) { $in = 0; next }
        push @corpus_lines, $l if $in;
    }
}
die "no perl blocks found in $CORPUS -- is the path right?\n" unless @corpus_lines;
printf "corpus perl-block lines: %d\n", scalar @corpus_lines;

my @t_files = sort( glob("$PERL_T/base/*.t"), glob("$PERL_T/comp/*.t"),
                    glob("$PERL_T/cmd/*.t") );
printf "perl t/ files: %d\n\n", scalar @t_files;

for my $pair (@IDIOMS) {
    my ( $name, $re ) = $pair->@*;
    my $in_corpus = grep { $_ =~ $re } @corpus_lines;

    my @where;
    for my $f (@t_files) {
        open my $fh, '<', $f or next;
        while ( my $l = <$fh> ) {
            next unless $l =~ $re;
            ( my $short = $f ) =~ s{^\Q$PERL_T\E/}{};
            push @where, "$short:$.";
            last;
        }
    }

    my $mark = ( !$in_corpus && @where ) ? 'ABSENT' : '';
    printf "%-6s %-28s corpus=%-3d t/=%s\n",
        $mark, $name, $in_corpus,
        ( @where ? join( ' ', @where[ 0 .. ( @where > 3 ? 2 : $#where ) ] )
                 : '(none)' );
}

print "\nABSENT = in perl's t/ and in no corpus perl block: a candidate to propose.\n";
