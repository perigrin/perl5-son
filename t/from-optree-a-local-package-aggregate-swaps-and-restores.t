# ABOUTME: `local @x` / `local %h` restored at a scope's exit is a slot rebind, as
# ABOUTME: `local *v` is: the save is a ref to the old aggregate, bound back at exit.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub write_src ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return $f;
}

sub run_perl ($f) { return scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null) }

sub producer_stderr ($src) {
    my $f = write_src($src);
    qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err >/dev/null);
    unlink $f;
    open my $e, '<', "$dir/err" or return ''; local $/; return <$e>;
}

sub round_trips ($src) {
    my $f    = write_src($src);
    my $want = run_perl($f);
    my $j    = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die; my $err = do { local $/; <$e> } =~ s/^\S+ syntax OK\n//mr;
    is $err, '', "the producer says nothing: $src" or return;
    my $d   = SoN::Deparse->new;
    my $out = $d->render(JSON::PP->new->decode($j));
    ok defined $out, '... renders' or diag($d->gap), return;
    is run_perl(write_src($out)), $want, '... and runs as perl does'
        or diag "--- emitted ---\n$out";
}

# `our @a = (1); sub g { local @a = (5); "@a" } print g(), " @a"` printed
# "5 5" through chalk for perl's "5 1" when the restore only rebound a name.
round_trips($_) for
    q{our @a = (1); sub g { local @a = (5); print "@a "; return } g(); print "@a\n";},
    q{our @a = (1); { local @a = (5); print "@a " } print "@a\n";},
    q{our %h = (k => 1); sub g { local %h = (k => 2); return $h{k} } print g(), $h{k}, "\n";},
    # A READER IN ANOTHER SUB sees the local inside the scope and the old one after.
    q{our @a = (1, 2); sub n { scalar @a } sub g { local @a = (7); return n() } print g(), n(), "\n";};

# At the program's own scope the restore is at its end: nothing sees it.
unlike producer_stderr(q{our @a = (1); local @a = (5); print "@a\n";}),
    qr/GAP: local on a package array or hash/, 'a local at program scope is a store';


# A VALUE RETURNED PAST THE RESTORE, read from the local aggregate: the read
# names its version (wire v2 stage 7), so the deparser holds it before the
# restore (it refused it by name while the read was the name itself).
round_trips(q{our @a = (1); sub g { local @a = (5); return "@a" } print g(), " @a\n";});

done_testing;
