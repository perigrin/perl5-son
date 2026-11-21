# ABOUTME: tools/wire-diff.pl's allow file names a graph everywhere, or (a third column) in one
# ABOUTME: wire only: a program's own graph is main::__PROGRAM__ in every wire, so it needs the file.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $dir = tempdir( CLEANUP => 1 );
make_path("$dir/old/probes", "$dir/new/probes");
sub put ($f, $v) { open my $o, '>', $f or die $!; print $o qq({"version":1,"methods":{"main::__PROGRAM__":{"nodes":[{"id":0,"op":"Start","inputs":[],"v":$v}]}}}); close $o }
put("$dir/old/probes/a.json", 1); put("$dir/new/probes/a.json", 2);
put("$dir/old/probes/b.json", 1); put("$dir/new/probes/b.json", 2);
open my $o, '>', "$dir/allow.tsv" or die $!;
print $o "main::__PROGRAM__\ta fix\tprobes/a.json\n";
close $o;
my $out = qx($^X tools/wire-diff.pl --allow $dir/allow.tsv $dir/old $dir/new 2>&1);
like $out, qr{^probes/a\.json: graph method main::__PROGRAM__ \(allowed\)$}m, 'the graph allowed in the wire named';
like $out, qr{^probes/b\.json: graph method main::__PROGRAM__$}m, '...and not in another';
like $out, qr/^# 1 of 2 wires differ$/m, 'one wire differs';
done_testing;
