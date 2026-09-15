use v5.42.0;
use lib '/home/perigrin/dev/perl5-son/lib';
use SoN::Deparse;
use JSON::PP;
my @files = @ARGV;
my ($ok,$gap,$diff)=(0,0,0);
for my $f (@files) {
    my $want = qx($^X $f 2>&1);
    my $json = qx($^X -I/home/perigrin/dev/perl5-son/lib -MO=SoN,json,not_package=SoN $f 2>/dev/null);
    my $data = eval { JSON::PP->new->decode($json) };
    unless ($data) { printf "%-26s NO GRAPH\n", $f; next }
    my $d = SoN::Deparse->new;
    my $src = $d->render($data);
    unless (defined $src) {
        my $g = $d->gap; $g =~ s/\n.*//s; $gap++;
        printf "%-26s %s\n", $f, $g; next;
    }
    my $tmp = "/tmp/oracle.$$.pl";
    open my $fh,'>',$tmp; print $fh $src; close $fh;
    my $got = qx($^X $tmp 2>&1); unlink $tmp;
    if ($got eq $want) { $ok++; printf "%-26s ROUND-TRIPS\n", $f }
    else { $diff++; printf "%-26s DIFFERS\n", $f }
}
printf "\n  round-trips=%d  differs=%d  refused=%d\n", $ok,$diff,$gap;
