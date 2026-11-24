# ABOUTME: A method that stores $_[0] writes the caller's invocant variable; the wire passes the
# ABOUTME: invocant as a value -- a GAP by name (final audit 2026-11-24, class H).
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub translate ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die $!;
    return join '', <$e>;
}

# Both printed the object for perl's replaced value.
for my $src (
    'package C; sub new { bless {}, shift } sub repl { $_[0] = "gone" } package main; my $o=C->new; $o->repl; print ref($o) ? "obj" : $o, "\n";',
    'package C; sub new { bless {}, shift } sub nul { $_[0] = undef } package main; my $o=C->new; $o->nul; print defined $o ? "d" : "u", "\n";',
) {
    like translate($src), qr/GAP: a method that stores \$_\[0\]/, "refused by name: $src";
}
# Not refused: a method writing another argument, or none; an invocant that
# is an element or a package scalar (passed as its location: it reaches it).
for my $src (
    'package C; sub new { bless {}, shift } sub repl { $_[0] = 5 } package main; my @o=(C->new); $o[0]->repl; print ref($o[0]) ? "obj" : $o[0], "\n";',
    'package C; our $o; sub new { bless {}, shift } sub repl { $_[0] = "g" } package main; $C::o=C->new; $C::o->repl; print ref($C::o) ? "obj" : $C::o, "\n";',
    'package C; sub new { bless {}, shift } sub m { $_[0]{k} = 1; 1 } package main; my $o=C->new; $o->m; print $o->{k}, "\n";',
    'package C; sub new { bless {}, shift } sub m { my $s = shift; $s = 5; 1 } package main; my $o=C->new; $o->m; print ref $o, "\n";',
) {
    unlike translate($src), qr/GAP:/, "not refused: $src";
}

done_testing;
