# ABOUTME: Key a chalk refusal message on the construct it names, so one missing
# ABOUTME: backend feature counts once however many cases and operands hit it.
package CorpusLlvmCause;
use v5.42.0;

# cause_key($message) -> the construct: no source location, no wrapper
# prefix, no quoted names or counts, and nothing past the first em dash
# (as a character or as its UTF-8 bytes, as chalk prints it), `;`,
# `.` or parenthesis, where the per-case detail starts.
sub cause_key ($m) {
    $m =~ s/\s+at \S+ line \d+(?:, <\S*> (?:line|chunk) \d+)?\.?\s*\z//;
    $m =~ s/^(?:GAP:\s*|LLVM backend:\s*|from_json failed:\s*)+//;
    $m =~ s/'[^']*'/X/g;
    $m =~ s/\s*(?:\x{2014}|\xe2\x80\x94|;|\.\s|\.\z|\s\().*//s;
    $m =~ s/\b\d+\b/N/g;
    $m =~ s/\s+/ /g;
    $m =~ s/\s+\z//;
    return substr($m, 0, 100);
}

1;
