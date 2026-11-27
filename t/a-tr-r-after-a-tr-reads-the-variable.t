# ABOUTME: A tr///r or s///r of a lexical a tr/// wrote reads the variable at its version, never the
# ABOUTME: earlier Transliterate node (which a consumer reads as the count: `22` for perl's `2cc`).
use v5.42.0;
use Test2::V0;
use JSON::PP;

# (fourth final audit, X6: the binding a destructive tr/// left on its demoted
# slot was taken as the /r form's subject -- B::SoN means the string after it,
# chalk reads a Transliterate used as a value as its count)
for my $src (
    'my $s = "bb"; my $t = $s =~ tr/b//; my $r = $s =~ tr/b/c/r; print "$t$r\n";',
    'my $s = "bb"; $s =~ tr/b/x/; my $r = $s =~ tr/x/c/r; print "$s$r\n";',
    'my $s = "bb"; $s =~ tr/b/x/; my $r = $s =~ s/x/c/r; print "$s$r\n";',
    'my $s = "ab"; for my $i (1..2) { $s =~ tr/ab/ba/; print $s =~ tr/a/z/r } print "\n";',
) {
    my $json = qx($^X -Ilib -MO=-q,SoN,json -e '$src' 2>/dev/null);
    my @n = JSON::PP->new->decode($json)->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %by = map { ( $_->{id} => $_ ) } @n;
    my @bad = grep {
        my $n = $_;
        $n->{op} =~ /\A(?:Transliterate|RegexSubst)\z/ && grep { ( $by{$_}{op} // '' ) eq 'Transliterate' } ( $n->{inputs} // [] )->@*
    } @n;
    is scalar(@bad), 0, "no tr/s/// subject is an earlier Transliterate: $src";
}
done_testing;
