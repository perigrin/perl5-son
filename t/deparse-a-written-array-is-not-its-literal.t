# ABOUTME: A lexical array written by push, an element store or a named sub is read as it now
# ABOUTME: stands: neither a bare `my @a` nor a shared file lexical is read back as its literal.

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


round_trips('my @a; push @a,1,2; my @b=@a; print scalar(@b), "\n";',
    'push into a bare-declared array, then a copy');
round_trips('my @a; $a[0]=1; my @b=@a; print scalar(@b), "\n";',
    'an element store into a bare-declared array, then a copy');
round_trips('my @a; unshift @a,3; push @a,4; my @b=@a; print "@b\n";',
    'unshift and push into a bare-declared array, copied, in list context');
round_trips('sub f { my @a; push @a, @_; my @b = @a; return scalar(@b) } print f(5,6,7), "\n";',
    'push into a bare-declared array inside a sub');
round_trips('my @a; for my $i (1..3) { push @a, $i } my @b=@a; print "@b\n";',
    'push in a loop into a bare-declared array, then a copy');
round_trips('my @F=(1,2); sub f { push @F, 3 } f(); print "@F\n";',
    'a named sub pushing to a file lexical array');
round_trips('my @F=(1,2); sub f { $F[2] = 3 } f(); print scalar(@F), "\n";',
    'a named sub storing an element of a file lexical array, then counted');
round_trips('my @F=(1,2); sub f { push @F, 3 } f(); my @c=@F; print "@c\n";',
    'a named sub pushing to a file lexical array, then a copy');
round_trips(q{my @a=(0); my $i=0; while ($i<3) { push @a, $i; $i++ } print "@a\n";},
    q{push in a loop body, then a list read after the loop});
round_trips(q{my $x=1; my @a=(0); if ($x) { shift @a } my @b=@a; print "@b|\n";},
    q{shift in an arm, then a copy after it});
round_trips(q{sub f { my @p; push @p, "a", "b"; return @p } print f(), "\n";},
    q{push into a bare-declared array, then returned});
round_trips(q{sub f { my @p = (1); shift @p; return @p } my $n = f(); print f(), "|$n\n";},
    q{shift from an array, then returned in list and scalar context});

round_trips(q{my %h; $h{a}=1; my %g=%h; print join(",",%g), "\n";},
    q{an element store into a bare-declared hash, then a copy});

# A BARE `my @a` stays a declaration ordered before every later write: a
# closure, a string eval, an element list-assign and a whole-array assign all
# write it after it is declared, and an unwritten one is still counted.
round_trips(q{my @a; my $c = sub { push @a, 1 }; $c->(); $c->(); print "@a\n";},
    q{a closure pushing to a bare-declared array});
round_trips(q{my @a; my $c = sub { $a[0] = 1 }; $c->(); print "@a\n";},
    q{a closure storing an element of a bare-declared array});
# A string eval with a lexical in scope refuses outright: it can write any of
# them unseen (t/from-optree-a-string-eval-sees-the-lexicals.t).
graph_of(q{my @a; eval 'push @a, 5'; print "@a\n";});
my $eval_err = producer_stderr();
like $eval_err, qr/GAP: a string eval with a lexical in scope [(]\@a[)]/,
    'a string eval pushing to a bare-declared array refuses';
round_trips(q{my @a; ($a[0],$a[1])=(3,4); print "@a\n";},
    q{an element list-assign into a bare-declared array});
round_trips(q{my $x=1; my @a; if ($x) { ($a[0],$a[1])=(3,4) } print "@a\n";},
    q{an element list-assign in an arm into a bare-declared array});
round_trips(q{my @a; @a = (1,2,3); push @a, 4; print "@a\n";},
    q{a whole-array assign then a push into a bare-declared array});
round_trips(q{my @a; (@a) = (1,2); print scalar(@a), "\n";},
    q{a parenthesised whole-array assign, then counted});
round_trips(q{my @a; my $n = (@a = (1,2)); print "$n|@a\n";},
    q{a whole-array assign in scalar context});
round_trips(q{sub f { my @p; return @p } my $n = f(); print defined $n ? "d" : "u", "\n";},
    q{an unwritten bare-declared array returned in scalar context});

# A BLOCK EVAL'S VALUE that is its last effect runs once, not twice.
round_trips(q{my @a; eval { push @a, 1 }; print "@a\n";},
    q{a block eval pushing to a bare-declared array});
round_trips(q{my @a=(9); eval { push @a, 1 }; print "@a\n";},
    q{a block eval pushing to an initialised array});
round_trips(q{my $r=[9]; eval { push @$r, 1 }; print "@$r\n";},
    q{a block eval pushing through a reference});
round_trips(q{my @a=(9); my $n = eval { push @a, 1 }; print "$n|@a\n";},
    q{a block eval's push, its value kept});

# A BARE PadAccess written through a reference is read as the container.
round_trips(q{sub fill { push @{$_[0]}, 1 } my @c; fill(\@c); print "@c\n";},
    q{a bare-declared array filled through a reference, then read});
round_trips(q{my @c; my $r=\@c; push @$r, 1; my @d = @c; print "@d\n";},
    q{a bare-declared array pushed through a reference, then a copy});

# A FLOATING INITIALISER THAT READS A PINNED COPY follows the copy: the copy
# is declared where the chain reaches it, so hoisted above it the reader
# named an undeclared aggregate.
round_trips(q{my @a; my @b=@a; my @c=(scalar(@b)); print "@c\n";},
    q{an array initialiser counting a pinned copy});
round_trips(q{my @a; my @b=@a; my %h=(n=>scalar(@b)); print "$h{n}\n";},
    q{a hash initialiser counting a pinned copy});
round_trips(q{my %g; my %h=%g; my @k=(scalar(keys %h)); print "@k\n";},
    q{an array initialiser counting the keys of a pinned hash copy});
round_trips(q{my @a; my @b=@a; my %h=(n=>$#b); print "$h{n}\n";},
    q{a hash initialiser reading the last index of a pinned copy});
round_trips(q{my @a; my @b=@a; my %h=(n=>$b[0] // "u"); print "$h{n}\n";},
    q{a hash initialiser reading an element of a pinned copy});
round_trips(q{my @a; my @b=@a; my @c=(1) x @b; print scalar(@c),"\n";},
    q{a repeat counted by a pinned copy});
round_trips(q{my @a; my %h=(x=>1); my @b=@a; my %g=(%h, n=>scalar(@b)); print "$g{n}\n";},
    q{a hash initialiser reading another hash and a pinned copy});

done_testing;
