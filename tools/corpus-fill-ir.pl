#!/usr/bin/perl
# ABOUTME: Fill (or check) each case in our copy of the corpora with B::SoN's graph
# ABOUTME: for its ```perl block, inline, as the YAML SoN::Render::WireYAML writes.
#
# t/corpus/mdtest holds our own copies of pvm's and Chalk's topic files (see
# its README). Each case gets the graph its ```perl block translates to,
# listed from the wire JSON as flow YAML any YAML parser reads -- so a
# consumer can take the corpus one stage at a time: the perl, the graph
# B::SoN gives it, and what perl says it does.
#
#   perl tools/corpus-fill-ir.pl [DIR...]           rewrite the blocks in place
#   perl tools/corpus-fill-ir.pl --check [DIR...]   write nothing; list each case
#                                                   whose block differs, exit 1
#
# DIR defaults to both copies. Each is read by its OWN corpus's convention,
# chosen by the directory's name (%CONVENTION). A `parses: no` case has no
# optree and gets no block. A graph the producer skips is listed under a
# top-level `refused:` key, so a refusal is recorded rather than looking like
# an absent graph.
use strict; use warnings;
use JSON::PP;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use SoN::Render::WireYAML;

# WHERE THE GRAPH GOES AND WHAT IS TRANSLATED, per corpus:
#
#   pvm    FORMAT.md reserves ```ir for B::SoN's graph, and a case is a whole
#          program, translated as written.
#   chalk  ```ir is Chalk's own hand-written spec (with its `L:` verdict), so
#          ours is ```son beside it; and a case is a FRAGMENT, translated the
#          way Chalk's harness runs it through B::SoN -- pragmas and class
#          declarations at file scope, the rest the body of
#          `sub corpus_case` (chalk t/bootstrap/corpus/son-e2e.t,
#          split_class_source, without its print rewrite: the spec is of the
#          sub's return value), all under `use 5.42.0;` -- the header Chalk's
#          behavior oracle compiles every fragment under
#          (MdtestCorpus::_run_expr_under_perl), and what a fragment like
#          `try { } catch ($e) { }` needs to compile at all.
my %CONVENTION = (
    pvm   => { tag => 'ir',  program => sub { $_[0] } },
    chalk => { tag => 'son', program => \&chalk_program },
);

my $check = @ARGV && $ARGV[0] eq '--check' ? shift @ARGV : 0;
my @dirs = @ARGV ? @ARGV
    : map { "$FindBin::Bin/../t/corpus/mdtest/$_" } sort keys %CONVENTION;
my $tmp = tempdir(CLEANUP => 1);

sub chalk_program {
    my ($src) = @_;
    (my $clean = $src) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;
    my (@head, @driver);
    my ($depth, $in_class) = (0, 0);
    for my $line (split /\n/, $clean) {
        if (!$in_class && $line =~ /^\s*(?:use|no)\s+/) { push @head, $line; next }
        $in_class = 1, $depth = 0 if !$in_class && $line =~ /^\s*class\s+\w/;
        if ($in_class) {
            push @head, $line;
            $depth += ($line =~ tr/{//);
            $depth -= ($line =~ tr/}//);
            $in_class = 0 if $depth <= 0;
            next;
        }
        push @driver, $line;
    }
    return join("\n", "use 5.42.0;", @head) . "\npackage main;\nsub corpus_case {\n"
         . join("\n", @driver) . "\n}\n";
}

sub listing {
    my ($src) = @_;
    my $f = "$tmp/case.pl";
    open my $o, '>', $f or die $!; print $o $src; close $o;
    # -q, as the round-trip census does: a BEGIN block's own output would
    # otherwise land in front of the JSON.
    my $json = qx($^X -I$FindBin::Bin/../lib -MO=-q,SoN,json,not_package=SoN $f 2>$tmp/err);
    my $err  = do { local (@ARGV, $/) = "$tmp/err"; <> } // '';
    my @refused = map { s/\Q$tmp\E\/case\.pl/CASE/gr }
                  grep { /^B::SoN: (?:skipped|INTERNAL)/ } split /\n/, $err;
    my $wire = eval { JSON::PP->new->decode($json) };
    my $text = $wire ? SoN::Render::WireYAML::render($wire) : '';
    push @refused, 'no wire JSON' unless $wire;
    # PERL DID NOT COMPILE IT: whatever graphs a BEGIN block left are not the
    # program's, so the block says so, with perl's first complaint, instead.
    if ($err =~ /had compilation errors/) {
        my ($why) = grep { length && !/had compilation errors|syntax OK|^B::SoN/ }
                    split /\n/, $err;
        $text = '';
        @refused = ('does not compile: '
            . (($why // 'no message') =~ s/ at \Q$f\E line \d+.*//r));
    }
    $text .= "refused: [\n"
           . join(",\n", map { '  ' . SoN::Render::WireYAML::_scalar(s/^B::SoN: //r) }
                          @refused)
           . "]\n" if @refused;
    return $text;
}

my ($cases, @drift) = (0);
for my $dir (@dirs) {
my ($name) = $dir =~ m{([^/]+)/*\z};
my $conv = $CONVENTION{$name}
    or die "$dir: no convention for a corpus named `$name`\n";
die "no corpus at $dir\n" unless -d $dir;
my $tag = $conv->{tag};
for my $md (sort glob "$dir/*.md") {
    open my $fh, '<', $md or die "$md: $!";
    my @lines = <$fh>;
    close $fh;
    my @out;
    my $i = 0;
    while ($i < @lines) {
        if ($lines[$i] !~ /^```perl\s*$/) { push @out, $lines[$i++]; next }

        # THE CASE: its perl block, then every fenced block up to the next
        # heading or perl block -- behavior, output, tokens, and ir if any.
        my @src;
        push @out, $lines[$i++];
        while ($i < @lines && $lines[$i] !~ /^```\s*$/) {
            push @src, $lines[$i];
            push @out, $lines[$i++];
        }
        push @out, $lines[$i++];
        my $src = join '', @src;
        if ($src !~ /\S/) { next }

        my ($parses_no, $ir_at, @tail) = (0, undef);
        while ($i < @lines && $lines[$i] !~ /^(?:## |```perl\s*$)/) {
            if ($lines[$i] =~ /^```(\w+)\s*$/) {
                my $btag = $1;
                my @blk = ($lines[$i++]);
                push @blk, $lines[$i++] while $i < @lines && $lines[$i] !~ /^```\s*$/;
                push @blk, $lines[$i++];
                $parses_no = 1 if $btag eq 'behavior' && grep { /^parses:\s*no\b/ } @blk;
                if ($btag eq $tag) { $ir_at = [ scalar(@tail), \@blk ] }
                push @tail, @blk;
                next;
            }
            push @tail, $lines[$i++];
        }
        if ($parses_no) { push @out, @tail; next }
        $cases++;

        my $want = listing($conv->{program}->($src));
        my @block = ("```$tag\n", $want, "```\n");
        if ($ir_at) {
            my ($at, $blk) = @$ir_at;
            push @drift, "$md: " . ($src =~ /\A(.{0,60})/ ? $1 : '')
                if join('', @$blk[1 .. $#$blk - 1]) ne $want;
            splice @tail, $at, scalar(@$blk), @block;
        }
        else {
            push @drift, "$md: (no $tag block) " . ($src =~ /\A(.{0,60})/ ? $1 : '');
            # After the case's last fenced block, before the blank lines and
            # prose that lead to the next case.
            my $last = -1;
            for my $k (0 .. $#tail) { $last = $k if $tail[$k] =~ /^```\s*$/ }
            splice @tail, $last + 1, 0, "\n", @block;
        }
        push @out, @tail;
    }
    next if $check;
    my $new = join '', @out;
    next if $new eq join '', @lines;
    open my $w, '>', $md or die "$md: $!";
    print $w $new;
    close $w;
}
}

printf "cases: %d\n", $cases;
printf "%s: %d\n", ($check ? 'drifted' : 'rewritten'), scalar @drift;
print "  $_\n" for @drift;
exit($check && @drift ? 1 : 0);
