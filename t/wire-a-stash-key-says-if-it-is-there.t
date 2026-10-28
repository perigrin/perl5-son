# ABOUTME: a constant-key read of %main:: says whether the key was there when
# ABOUTME: the program compiled -- unless the toolchain's own load made it.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    my $w = eval { JSON::PP->new->decode($j) } or return [];
    return $w->{methods}{'main::__PROGRAM__'}{nodes} // [];
}

sub has_of ($nodes, $key) {
    my %by = map { $_->{id} => $_ } @$nodes;
    my ($n) = grep {
        $_->{op} =~ /\A(?:Exists|Subscript)\z/
            && ( ( $by{ $_->{inputs}[1] } // {} )->{fields}{value} // '' ) eq $key
    } @$nodes;
    return $n ? $n->{fields}{stash_has} : 'no node';
}

# pvm 013 316 317 346: an import made the key, `our` made it, nothing did.
my $n = nodes_of(qq{use POSIX;\nour \$answer = 1;\nprint exists \$::{answer}, exists \$::{nosuch}, (\$main::{"floor"} ? 1 : 0), "\\n";\n});
is has_of($n, 'answer'), 1, 'our made it';
is has_of($n, 'nosuch'), 0, 'nothing made it';
is has_of($n, 'floor'), 1, 'an import made it';

# B::SoN's own code makes SIG (and others) in main:: before the program
# compiles; plain perl would not have it, so no fact is given.
$n = nodes_of(qq{print exists \$::{SIG} ? 1 : 0, "\\n";\n});
is has_of($n, 'SIG'), undef, "a key the toolchain made is not answered";

done_testing;
