#!/usr/bin/perl
# ABOUTME: Fill (or check) each pvm corpus case's ```ir block with B::SoN's graph
# ABOUTME: for its ```perl block, as the compact YAML SoN::Render::WireYAML writes.
#
# pvm's FORMAT.md reserves ```ir for "the GRAPH answer, which is B::SoN's". A
# case's graph is the one its ```perl block translates to, listed from the
# wire JSON as flow YAML any YAML parser reads -- so a consumer (chalk) can
# take the corpus one stage at a time: the perl, the graph B::SoN gives it, and
# the output perl prints. See SoN::Render::WireYAML for the shape.
#
#   perl tools/corpus-fill-ir.pl [DIR]           rewrite the ir blocks in place
#   perl tools/corpus-fill-ir.pl --check [DIR]   write nothing; list each case
#                                                whose block differs, exit 1
#
# DIR defaults to $SON_CORPUS. A `parses: no` case has no optree and gets no
# block. A graph the producer skips is listed under a top-level `refused:` key,
# so a refusal is recorded rather than looking like an absent graph.
use strict; use warnings;
use JSON::PP;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use SoN::Render::WireYAML;

my $check = @ARGV && $ARGV[0] eq '--check' ? shift @ARGV : 0;
my $C = shift(@ARGV) // $ENV{SON_CORPUS}
    or die "usage: $0 [--check] DIR (or set SON_CORPUS)\n";
die "no corpus at $C\n" unless -d $C;
my $tmp = tempdir(CLEANUP => 1);

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
    $text .= "refused: [\n"
           . join(",\n", map { '  ' . SoN::Render::WireYAML::_scalar(s/^B::SoN: //r) }
                          @refused)
           . "]\n" if @refused;
    return $text;
}

my ($cases, @drift) = (0);
for my $md (sort glob "$C/*.md") {
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

        my ($parses_no, $ir_at, @tail) = (0, undef);
        while ($i < @lines && $lines[$i] !~ /^(?:## |```perl\s*$)/) {
            if ($lines[$i] =~ /^```(\w+)\s*$/) {
                my $tag = $1;
                my @blk = ($lines[$i++]);
                push @blk, $lines[$i++] while $i < @lines && $lines[$i] !~ /^```\s*$/;
                push @blk, $lines[$i++];
                $parses_no = 1 if $tag eq 'behavior' && grep { /^parses:\s*no\b/ } @blk;
                if ($tag eq 'ir') { $ir_at = [ scalar(@tail), \@blk ] }
                push @tail, @blk;
                next;
            }
            push @tail, $lines[$i++];
        }
        if ($parses_no) { push @out, @tail; next }
        $cases++;

        my $want = listing($src);
        my @block = ("```ir\n", $want, "```\n");
        if ($ir_at) {
            my ($at, $blk) = @$ir_at;
            push @drift, "$md: " . ($src =~ /\A(.{0,60})/ ? $1 : '')
                if join('', @$blk[1 .. $#$blk - 1]) ne $want;
            splice @tail, $at, scalar(@$blk), @block;
        }
        else {
            push @drift, "$md: (no ir block) " . ($src =~ /\A(.{0,60})/ ? $1 : '');
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

printf "cases: %d\n", $cases;
printf "%s: %d\n", ($check ? 'drifted' : 'rewritten'), scalar @drift;
print "  $_\n" for @drift;
exit($check && @drift ? 1 : 0);
