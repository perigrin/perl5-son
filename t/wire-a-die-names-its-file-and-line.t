# ABOUTME: a die carries the file and line of its statement, which perl's
# ABOUTME: message names when it does not end in a newline.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src, $graph) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    my $w = eval { JSON::PP->new->decode($j) } or return ([], $f);
    return ($w->{methods}{$graph}{nodes} // [], $f);
}

# Without them a die whose message may not end in a newline was refused: the
# message perl makes is "MSG at FILE line N.\n" (pvm 063 136).
my ($nodes, $f) = nodes_of(qq{my \$x = 1;\n\nif (\$x) { die "no newline" }\nprint "ok\\n";\n}, 'main::__PROGRAM__');
my ($u) = grep { $_->{op} eq 'Unwind' } @$nodes;
ok $u, 'an Unwind';
is $u->{fields}{file}, $f, 'it names the file perl compiled';
is $u->{fields}{line}, 3, 'and the line of its statement';

done_testing;
