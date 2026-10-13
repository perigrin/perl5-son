# ABOUTME: A module's lifted subs are named in main, and a required file starts in the
# ABOUTME: requirer's package: the emission must say main, or the subs land elsewhere.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);
mkdir "$dir/orig"; mkdir "$dir/emit";

# The module is required FROM ANOTHER PACKAGE, as chalk's TestPipeline loads
# TypeInferenceActions: the file is compiled in package TestPipeline there.
sub required_from_another_package ($lib, $call) {
    return scalar qx(/usr/bin/timeout 10 $^X -I$lib -e 'package Other; require M; print $call, "\\n"' 2>&1);
}

sub module_round_trips ($src, $call, $name) {
    open my $fh, '>', "$dir/orig/M.pm" or die $!; print $fh $src; close $fh;
    my $want = required_from_another_package("$dir/orig", $call);
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $dir/orig/M.pm 2>$dir/err);
    my $err = do { local (@ARGV, $/) = "$dir/err"; <> } =~ s/^\S+ syntax OK\n//mr;
    is $err, '', "$name: the producer says nothing";
    my $d = SoN::Deparse->new;
    my $out = $d->render(JSON::PP->new->decode($json))
        // return fail "$name: renders (" . ($d->gap // '?') . ')';
    open $fh, '>', "$dir/emit/M.pm" or die $!; print $fh $out; close $fh;
    is required_from_another_package("$dir/emit", $call), $want, $name
        or diag "--- emitted ---\n$out";
}

module_round_trips("package M;\nuse v5.36;\nmy \$p = sub (\$n) { \$n + 1 };\nsub get (\$x) { \$p->(\$x) }\n1;\n",
    'M::get(1)', 'an anon sub held in a file lexical');
module_round_trips("use v5.36;\nuse experimental 'class';\nclass M {\n  my \$p = sub (\$n) { \$n * 2 };\n  my sub f (\$x) { \$p->(\$x) }\n  method m (\$v) { f(\$v) }\n}\n1;\n",
    'M->new->m(4)', 'a lexical sub closing over a class-block lexical');

done_testing;
