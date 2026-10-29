# ABOUTME: `&&`/`||` in list context whose right side is a list of several
# ABOUTME: values is refused: the walk kept only its last value.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub warnings_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

# `my @r = @a && (3, 4, 5)` reached the wire as And(Count, 5): one element
# for perl's three.
like warnings_of(qq{my \@a = (1, 2);\nmy \@r = \@a && (3, 4, 5);\nprint scalar(\@r), "\\n";\n}),
    qr/GAP: a short-circuit whose right side is a list/, 'a list right side';
unlike warnings_of(qq{my \@a = (1, 2);\nmy \$r = \@a && 5;\nprint "\$r\\n";\n}),
    qr/GAP: a short-circuit/, 'a single value is not refused';

done_testing;
