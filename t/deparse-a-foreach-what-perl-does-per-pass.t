# ABOUTME: A foreach whose body reshapes its own list, nests in a loop that grows it, writes a
# ABOUTME: package iterator, or binds several iterators: each round trips or refuses by name.

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


sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

# PERL READS THE LIVE ARRAY EACH PASS. A shift, push, splice or clear in the
# body moves the elements under the counter the lowering indexes by, and the
# element read was spelled after the shift: `2|2` for perl's `1|2`.
my $RESHAPE = qr/GAP: a foreach whose body reshapes the array it iterates/;
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $s .= $x; shift @a } print "$s|@a\n" } f();},
    $RESHAPE, 'a shift of a bare-declared array in its own loop');
refuses(q{sub f { my @a = (1, 2); my $s=""; for my $x (@a) { $s .= $x; shift @a } print "$s|@a\n" } f();},
    $RESHAPE, 'a shift of an assigned array in its own loop');
refuses(q{use v5.42; sub f($r) { my $s=""; for (@$r) { $s .= $_; shift @$r } "$s|@$r" } print f([1,2]), "\n";},
    $RESHAPE, 'a shift of a dereferenced array in its own loop');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $s .= $x; @a = () if $x == 1 } print "$s|@a\n" } f();},
    $RESHAPE, 'a clear of the array in its own loop');
refuses(q{sub f { my @a = (1, 2); my $s=""; for my $x (@a) { $s .= $x; push @a, 3 if $x == 1 } print "$s|@a\n" } f();},
    $RESHAPE, 'a push onto the array in its own loop');
refuses(q{sub f { my @a = (1, 2, 3); my $s=""; for my $x (@a) { $s .= $x; splice @a, 1, 1 } print "$s|@a\n" } f();},
    $RESHAPE, 'a splice of the array in its own loop');
refuses(q{sub f { my @a = (1, 2, 3); my $s=""; for my $x (@a) { $s .= $x; undef @a } print "$s|@a\n" } f();},
    $RESHAPE, 'an undef of the array in its own loop');
# Another array is not this one.
round_trips(q{sub f { my @a = (1, 2); my @o; for my $x (@a) { push @o, $x * 2; shift @o if @o > 1 } "@a|@o" } print f(), "\n";},
    'a push and shift of another array in the loop');
round_trips(q{use v5.42; sub f($r) { my @o; for (@$r) { push @o, $_ } "@o" } print f([1,2]), "\n";},
    'a push onto a lexical inside a loop over a deref');
round_trips(q{use v5.42; sub f($r, $q) { for (@$r) { push @$q, $_ * 2 } "@$q" } print f([1,2], [0]), "\n";},
    'a push onto another deref inside a loop over a deref');
refuses(q{use v5.42; sub f($h) { my $s = ""; for ($h->{q}->@*) { $s .= $_; push $h->{q}->@*, 3 if $_ == 1 } $s } print f({q => [1,2]}), "\n";},
    $RESHAPE, 'a push onto the same field deref inside its loop');

# A NESTED LOOP OVER AN ARRAY was invisible to the outer loop's scout: the scout
# binds every slot to a placeholder, the placeholder is no array, and the inner
# foreach refused there -- so the outer loop built no Phi for what the inner
# body writes and the accumulator restarted every pass (`11` for `111`).
round_trips(q{sub f { my @a; push @a, 1; my $s=""; for my $k (1..2) { for my $x (@a) { $s.=$x } push @a, $k } print "$s\n" } f();},
    'an inner loop over a bare array the outer loop pushes');
round_trips(q{sub f { my @a = (1); my $s=""; for my $k (1..2) { for my $x (@a) { $s.=$x } } print "$s\n" } f();},
    'an accumulator written by an inner array loop');
round_trips(q{sub f { my @a = (1); my $s=""; my $k=0; while ($k++ < 2) { for my $x (@a) { $s.=$x } } print "$s\n" } f();},
    'an inner array loop in a while');
round_trips(q{sub f { my @a = (1); my $s=""; for my $k (1..2) { for my $x (@a) { $s.=$x } $s .= "-" } print "$s\n" } f();},
    'an inner array loop then a write in the outer body');
round_trips(q{sub f { my @a = (1,2); my $s=""; for my $k (@a) { for my $x (@a) { $s.="$k$x" } } print "$s\n" } f();},
    'an array loop inside an array loop');

# THE SAME MISS WITHOUT AN INNER LOOP: a C-style `for` with nested `next`
# guards ahead of it kept its scout from reaching the increment of the second
# loop, which then emitted `$i = $i` and never terminated (chalk's
# StructPromotion::_rewrite_method_body). The real walk sees the write.
refuses(q{sub f { my ($b) = @_; my %r; for (my $i = 0; $i < scalar(@$b); $i++) { my $s = $b->[$i]; next unless defined $s; if ($s > 1) { next unless $s > 2; $r{$i} = 1 } } for (my $i = 0; $i < @$b; $i++) { next if $r{$i}; print $i } print "\n" } f([1,2,3,undef,5]);},
    qr/GAP: a loop body writes a variable its scout missed/, 'a C-style loop whose scout misses its increment');

# PERL LOCALIZES A PACKAGE ITERATOR: whatever the body writes, the variable
# holds its pre-loop value again after the loop.
round_trips(q{use v5.42; our $p = 0; sub f($r) { my $s=""; for $p (@$r) { $p *= 2 } "@$r|$p" } print f([1,2]), "\n";},
    'a package iterator written over a deref is restored');
round_trips(q{our $p = 0; sub f { my @a = (1,2); for $p (@a) { $p .= "x" } "@a|$p" } print f(), "\n";},
    'a package iterator written over an array is restored');
round_trips(q{our $p = 0; sub f { my $s = ""; for $p (1..2) { $p .= "x"; $s .= $p } "$s|$p" } print f(), "\n";},
    'a package iterator written over a range is restored');
round_trips(q{$_ = "z"; sub f { my @a = (1,2); for (@a) { $_ .= "x" } "@a|$_" } print f(), "\n";},
    'an implicit $_ written in the body is restored');
round_trips(q{our $p = 5; sub f { my @a = (1,2); my $s=""; for $p (@a) { $s .= $p } "$s|$p" } print f(), "\n";},
    'a package iterator only read keeps its value');

# SEVERAL ITERATORS take several elements per pass; the single-iterator
# lowering bound only the first and left the rest undef.
my $MULTI = qr/GAP: a foreach with several iterator variables/;
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my ($k, $v) (@a) { $s .= "$k$v" } $s } print f(), "\n";},
    $MULTI, 'two iterators over a bare array');
refuses(q{sub f { my @a = (1,2); my $s=""; for my ($k, $v) (@a) { $s .= "$k$v" } $s } print f(), "\n";},
    $MULTI, 'two iterators over an assigned array');
refuses(q{use v5.42; sub f($r) { my $s=""; for my ($k, $v) (@$r) { $s .= "$k$v" } $s } print f([1,2]), "\n";},
    $MULTI, 'two iterators over a deref');
refuses(q{sub f { my $s=""; for my ($k, $v) (1..4) { $s .= "$k$v" } $s } print f(), "\n";},
    $MULTI, 'two iterators over a range');
refuses(q{sub f { my $s=""; for my ($k, $v, $w) (1,2,3) { $s .= "$k$v$w" } $s } print f(), "\n";},
    $MULTI, 'three iterators over a list');

done_testing;
