# ABOUTME: Gate 3's rule for which chalk test files read lib/ as source -- those
# ABOUTME: measure the emitted text, not the program, and are deferred.
package ChalkGate3;
use v5.42.0;
use Exporter 'import';
our @EXPORT_OK = qw(reads_source_text);

# A TEST READS THE SOURCE when it names a lib/Chalk module path or walks lib/.
# Quoted (`'lib/Chalk/X.pm'`), in a qw() list, or built on the repo root
# (`"$repo_root/lib/Chalk/X.pm"`) alike: the quoted form alone left two
# LLVM tests that grep Context.pm's text among those measured. Not
# `t/lib/Chalk/...`, a test helper, and not a path in a comment.
sub reads_source_text ($src) {
    return 1 if $src =~ m{File::Find|glob\(.*lib};
    for my $line (split /\n/, $src) {
        next if $line =~ /^\s*#/;
        return 1 if $line =~ m{(?<![\w.])(?<!\bt/)lib/Chalk(?:[A-Za-z0-9/_:]*\.pm\b|/['"])};
    }
    return 0;
}

1;
