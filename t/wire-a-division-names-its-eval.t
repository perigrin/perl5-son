# ABOUTME: a division that may die names the block eval whose body made it,
# ABOUTME: and its statement's file and line, which perl's message names.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    my $w = eval { JSON::PP->new->decode($j) } or return ([], $f);
    return ($w->{methods}{'main::__PROGRAM__'}{nodes} // [], $f);
}

# A die from a division in an eval's body is caught by that eval; one made
# outside it is not -- chalk could not tell them apart (pvm 006 062).
my ($nodes, $f) = nodes_of(qq{my \$d = \$ENV{X} // 0;\nmy \$q = 6 / (\$d + 1);\nmy \$r = eval { 10 / \$d } // "t";\nprint "\$q \$r\\n";\n});
my @div = grep { $_->{op} eq 'Divide' } @$nodes;
is scalar(@div), 2, 'two divisions';
my ($in)  = grep { defined $_->{fields}{eval_id} } @div;
my ($out) = grep { !defined $_->{fields}{eval_id} } @div;
ok $in && $out, 'one names an eval, one does not';
is $in->{fields}{line}, 3, "the eval's division names its line";
is $in->{fields}{file}, $f, '...and its file';

done_testing;
