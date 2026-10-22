# ABOUTME: Read the cases of a pvm-convention mdtest corpus: each ```perl block
# ABOUTME: paired with the ```output block that follows it.
package PvmCorpus;
use v5.42.0;
use Exporter 'import';
our @EXPORT_OK = qw(read_cases);

# read_cases($dir) -> ({ file, src, want }, ...) over $dir/*.md, in order. A
# perl block with no output block after it is not a case.
sub read_cases ($dir) {
    my @cases;
    for my $md (sort glob "$dir/*.md") {
        open my $fh, '<', $md or die "$md: $!";
        my @lines = <$fh>;
        close $fh;
        my ($i, $cur) = (0, undef);
        while ($i < @lines) {
            if ($lines[$i] =~ /^```(perl|output)\s*$/) {
                my $kind = $1;
                my @body;
                $i++;
                push @body, $lines[$i++] while $i < @lines && $lines[$i] !~ /^```\s*$/;
                $i++;
                if ($kind eq 'perl') { $cur = { file => $md, src => join('', @body) } }
                elsif ($cur) { $cur->{want} = join('', @body); push @cases, $cur; $cur = undef }
                next;
            }
            $i++;
        }
    }
    return @cases;
}

1;
