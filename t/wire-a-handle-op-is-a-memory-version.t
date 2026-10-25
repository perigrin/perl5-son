# ABOUTME: open, readline, eof and close on a lexical handle each advance memory, so a read
# ABOUTME: of what they changed -- the array a readline filled -- is ordered after them.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# A HANDLE'S STATE IS MEMORY. `my @l = <$fh>; print scalar(@l)` read @l at
# the memory from before the open -- ordered by memory, a consumer built
# @l before the open ran and read an unopened handle.
my $src = <<'SRC';
open(my $fh, "<", \"one\ntwo\n");
my @l = <$fh>;
print scalar(@l), " ", eof($fh) ? "eof" : "more", "\n";
close($fh);
SRC

my $data  = graph_of($src);
my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my %by_id = map { $_->{id} => $_ } @nodes;
my %call  = map { $_->{fields}{name} => $_ } grep { $_->{op} eq 'Call' } @nodes;
for my $n (qw(open readline eof close)) {
    ok $call{$n}{fields}{memory_input}, "$n takes the memory before it";
}
my ($count) = grep { $_->{op} eq 'Count' } @nodes;
is $count->{inputs}[1], $call{readline}{id}, 'the count of @l reads the memory the readline made';

my $d = SoN::Deparse->new;
my $out = $d->render($data);
if (defined $out) { is run_perl($out), run_perl($src), 'renders to the same output' }
else              { like $d->gap // '', qr/\S/, 'or refuses it by name' }

done_testing;
