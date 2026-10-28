# ABOUTME: `local @x` / `local %h` restored at a scope's exit is refused by
# ABOUTME: name: its save was the name's SSA binding, and no store put it back.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub producer_stderr ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err >/dev/null);
    unlink $f;
    open my $e, '<', "$dir/err" or return ''; local $/; return <$e>;
}

# `our @a = (1); sub g { local @a = (5); "@a" } print g(), " @a"` printed
# "5 5" through chalk for perl's "5 1": inside g nothing was bound to save,
# and a save that was bound restored a name, not the package's storage.
for my $src (
    q{our @a = (1); sub g { local @a = (5); return "@a" } print g(), " @a\n";},
    q{our @a = (1); { local @a = (5); print "@a " } print "@a\n";},
    q{our %h = (k => 1); sub g { local %h = (k => 2); return $h{k} } print g(), $h{k}, "\n";},
) {
    like producer_stderr($src), qr/GAP: local on a package array or hash/, "refused by name: $src";
}

# At the program's own scope the restore is at its end: nothing sees it.
unlike producer_stderr(q{our @a = (1); local @a = (5); print "@a\n";}),
    qr/GAP: local on a package array or hash/, 'a local at program scope is a store';

done_testing;
