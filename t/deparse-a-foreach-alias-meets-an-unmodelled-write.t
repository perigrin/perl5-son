# ABOUTME: A foreach alias read meets a write the stale-read pass must see -- a hole, a
# ABOUTME: substr, a local, an s/// or a vec on an element: each round trips or refuses by name.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

# Either the emission matches perl, or the deparser refuses naming $cause.
sub round_trips_or_refuses ($src, $cause, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    return like $d->gap // q{}, $cause, "$name: refused, naming its cause"
        unless defined $out;
    my $got = run_perl($out);
    is $got, run_perl($src), $name
        or diag "--- emitted ---\n$out";
}

# A HOLE IS NOT VIVIFIED BY THE ALIAS. perl's foreach aliases a missing
# element without creating it. An array with holes is bare-declared, an
# unproven list, and a body that stores into it refuses.
my $UNPROVEN = qr/GAP: a foreach over an unproven list .* whose body may reach the list other than through its iterator/;
refuses(q{sub f { my @a; $a[2] = 1; my $s = ""; for my $x (@a) { $s .= defined $x ? 1 : 0; $a[5] = 1; $s .= defined $x ? 1 : 0 } print $s, (exists $a[0] ? "e" : "n"), scalar(@a), "\n" } f();},
    $UNPROVEN, 'a hole the alias passes over stays a hole');
refuses(q{sub f { my @a; $a[1] = 1; my $s = ""; for my $x (@a) { $a[3] = 2; $s .= $x // "u" } print $s, (exists $a[0] ? "e" : "n"), "\n" } f();},
    $UNPROVEN, 'a hole read after a store elsewhere');
refuses(q{sub f { my @a; $a[1] = 1; my $s = ""; for my $x (@a) { $a[0] = 5; $s .= $x // "u" } print $s, (exists $a[0] ? "e" : "n"), "\n" } f();},
    $UNPROVEN, 'a hole the body fills is seen through the alias');
round_trips_or_refuses(q{sub f { my $r = []; $r->[1] = 1; my $s = ""; for my $x (@$r) { $r->[3] = 2; $s .= $x // "u" } print $s, (exists $r->[0] ? "e" : "n"), "\n" } f();},
    qr/GAP: an element read in a loop is spelled after a store/, 'a hole in a dereferenced array');
refuses(q{sub f { my @a = (1, 2); my $s = ""; for my $x (@a) { $a[1] = 5; $s .= $x; shift @a if @a > 1 } print "$s|@a\n" } f();},
    qr/GAP: a foreach whose body reshapes the array it iterates/, 'an existing element read after a shift');

# A BUILTIN THAT WRITES ITS FIRST ARGUMENT IN PLACE overtakes an alias read.
my $STALE = qr/GAP: an element read in a loop is spelled after a store/;
for my $w ('substr($a[0], 0, 1, "z")', 'substr($a[0], 0, 1) = "z"') {
    my $src = qq{sub f { my \@a = (1,2); my \$s = ""; for my \$x (\@a) { \$a[1] = 5; \$s .= \$x; $w; } print "\$s|\@a\\n" } f();};
    round_trips_or_refuses($src, $STALE, "$w after the alias read");
}
round_trips_or_refuses(q{sub f { my @a = (1,2); my $s = ""; for my $x (@a) { substr($a[0], 0, 1, "z"); $s .= $x } print "$s|@a\n" } f();},
    $STALE, 'a substr before the alias read');
round_trips_or_refuses(q{sub f { my @a = ("ab","cd"); my $s = ""; for my $x (@a) { $a[1] = "q"; $s .= substr($x, 0, 1) } print "$s|@a\n" } f();},
    $STALE, 'a reading substr of the alias');

# A LOCAL ON AN ELEMENT restores it at scope exit; a plain store does not.
my $LOCAL = qr/GAP: local on an array or hash element/;
refuses(q{sub f { my @a = (1,2); my $s = ""; for my $x (@a) { $s .= $x; local $a[0] = 5; $s .= $x } print "$s|@a\n" } f();},
    $LOCAL, 'a local element in a foreach body');
refuses(q{sub f { my @a = (1,2); { local $a[0] = 5; print "@a\n" } print "@a\n" } f();},
    $LOCAL, 'a local array element in a block');
refuses(q{sub f { my %h = (a => 1); { local $h{a} = 5; print "$h{a}\n" } print "$h{a}\n" } f();},
    $LOCAL, 'a local hash element in a block');
refuses(q{sub f { my $s = { c => 1 }; { local $s->{c} = 2; print $s->{c} } print $s->{c}, "\n" } f();},
    $LOCAL, 'a local element through a reference');
# AT PROGRAM SCOPE THE RESTORE IS AT PROGRAM END, after every statement, so a
# plain store says what the program can see: pvm's corpus silences `warn`
# with `local $SIG{__WARN__} = sub { }` this way. A block, a loop body or a
# sub still restores before the program ends.
round_trips(q{local $SIG{__WARN__} = sub { }; my $n = warn "a"; print "$n\n";},
    'a local element at program scope');
round_trips(q{our %h = (a => 1); local $h{a} = 5; print "$h{a}\n";},
    'a local package hash element at program scope');
refuses(q{our %h = (a => 1); if (1) { local $h{a} = 5; print "$h{a}\n" } print "$h{a}\n";},
    $LOCAL, 'a local element in an if block at program scope');
refuses(q{our %h = (a => 1); for my $k (1) { local $h{a} = 5 } print "$h{a}\n";},
    $LOCAL, 'a local element in a loop at program scope');

# AN s/// ON ANYTHING BUT A NAMED SCALAR was bound to $_.
my $SUBST = qr/GAP: s\/\/\/ on a target that is not a named scalar/;
refuses(q{sub f { my @a = (1,2); my $s = ""; for my $x (@a) { $a[1] = 5; $s .= $x; $a[0] =~ s/1/z/; } print "$s|@a\n" } f();},
    $SUBST, 'an s/// on an element in a foreach body');
refuses(q{sub f { my @a = (1,2); $a[0] =~ s/1/z/; print "@a\n" } f();},
    $SUBST, 'an s/// on an array element');
refuses(q{sub f { my $h = { a => 1 }; $h->{a} =~ s/1/z/; print "$h->{a}\n" } f();},
    $SUBST, 'an s/// on a hash element through a reference');
refuses(q{our %h = (a => 1); $h{a} =~ s/1/z/; print "$h{a}\n";},
    $SUBST, 'an s/// on a package hash element');
# `(my $t = $s) =~ s///` writes $t, the slot the assignment just bound.
round_trips(q{sub f { my $raw = $_[0]; (my $b = $raw) =~ s/^x//; print "$b|$raw\n" } f("xy");},
    'an s/// on a lexical assignment leaves its source alone');
round_trips(q{our $g = "xa"; (my $b = $g) =~ s/x/y/; print "$b|$g\n";},
    'an s/// on an assignment from a package scalar');
round_trips(q{sub f { my $h = { a => "x1" }; (my $t = $h->{a}) =~ s/1/z/; print "$t|$h->{a}\n" } f();},
    'an s/// on an assignment from an element');
round_trips(q{sub f { my @p = qw($a @b); my @o; for my $p (@p) { (my $n = $p) =~ s/^[\$\@]//; push @o, $n } print "@o|@p\n" } f();},
    'an s/// on an assignment from a foreach alias');
round_trips(q{sub f { my ($raw) = @_; my $o = ""; for my $i (1..2) { (my $b = $raw) =~ s/^x/y/; $o .= "$i$b" } print "$o|$raw\n" } f("xy");},
    'an s/// on an assignment in a range loop');
round_trips(q{sub f { my ($raw) = @_; my $o = ""; my $i = 0; while ($i++ < 2) { (my $b = $raw) =~ s/^x/z/; $o .= $b; $raw .= "x" } print "$o|$raw\n" } f("xy");},
    'an s/// on an assignment in a while loop');
round_trips_or_refuses(q{sub f { my $s = "aaa"; my $n = ((my $t = $s) =~ s/a/b/g); print "$n|$t|$s\n" } f();},
    qr/GAP: a counted s\/\/\/ whose subject/, 'a counted s/// on an assignment');
round_trips(q{our $g = "a1"; $g =~ s/1/z/; print "$g\n";}, 'an s/// on a package scalar');
round_trips(q{$_ = "a1"; s/1/z/; print "$_\n";}, 'an s/// on the implicit $_');
round_trips(q{sub f { my $t = "a1"; $t =~ s/1/z/; print "$t\n" } f();}, 'an s/// on a lexical');

# AN LVALUE vec WAS DROPPED.
my $VEC = qr/GAP: an lvalue vec/;
refuses(q{sub f { my @a = ("a","b"); my $s = ""; for my $x (@a) { $a[1] = "c"; $s .= $x; vec($a[0], 0, 8) = 65; } print "$s|@a\n" } f();},
    $VEC, 'a vec store in a foreach body');
refuses(q{sub f { my $s = "ab"; vec($s, 0, 8) = 65; print "$s\n" } f();},
    $VEC, 'a vec store into a lexical');
refuses(q{our $g = "ab"; vec($g, 0, 8) = 65; print "$g\n";},
    $VEC, 'a vec store into a package scalar');
round_trips(q{sub f { my $s = "ab"; print vec($s, 0, 8), "\n" } f();}, 'a vec read');

done_testing;
