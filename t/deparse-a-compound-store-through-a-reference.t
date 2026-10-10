# ABOUTME: A compound assignment through a scalar reference (`$$r += 2`) stores its
# ABOUTME: result back through the reference rather than computing it and dropping it.

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


round_trips('my $v=1; my $r = \$v; $$r += 2; print "$v\n";',
    'top level: += through a ref to a lexical');
round_trips('sub f { my $r = shift; $$r *= 3; return } my $v=2; f(\$v); print "$v\n";',
    'in a sub: *= through a ref argument');
round_trips('our $g=4; my $r = \$g; $$r -= 1; print "$g\n";',
    'a ref to a package scalar');
round_trips('my $v=1; my @rs = (\$v); ${$rs[0]} += 4; print "$v\n";',
    'a ref fetched from an array element');
round_trips('my $v=0; my $r = \$v; $$r += $_ for 1..4; print "$v\n";',
    'in a loop body');
round_trips('my $v=1; my $r = \$v; my $w = ($$r += 5); print "$v $w\n";',
    'the compound in scalar value context');
round_trips('my $v=1; my $r = \$v; $$r += 2; $$r **= 2; print "$v ", $$r, "\n";',
    'two compounds in sequence, then a read through the ref');
round_trips('my $v=1; my $r = \$v; $$r++; print "$v\n";',
    'a postfix increment through a ref');
round_trips('my $v=1; my $r = \$v; my $w = ++$$r; my $u = $$r--; print "$v $w $u\n";',
    'pre and post forms in value context');
round_trips('sub f { my $r = shift; $$r++ for 1..3; return } my $v=2; f(\$v); print "$v\n";',
    'an increment through a ref argument in a loop');

# A read through the ref BEFORE the store keeps the old value: the store
# must not float above it, nor the read below it.
round_trips(q{my $v=1; my $r=\$v; my $a = $$r; $$r += 1; print "$a\n";},
    q{a plain read before +=});
round_trips(q{my $v=1; my $r=\$v; my $a = $$r; $$r++; print "$a\n";},
    q{a plain read before ++});
round_trips(q{sub f { my $r = shift; my $old = $$r; $$r += 10; return $old } my $v=1; print f(\$v), "\n";},
    q{save the old value, += through a ref argument, return it});
round_trips(q{sub f { my $r = shift; my $old = $$r; $$r++; return $old } my $v=1; print f(\$v), "\n";},
    q{save the old value, ++ through a ref argument, return it});
round_trips(q{my $v=1; my $r=\$v; my $a = $$r + 0; $$r *= 5; print "$a\n";},
    q{a read inside an expression before *=});
round_trips(q{my $v=1; my $r=\$v; my @s = ($$r); $$r += 1; print "@s\n";},
    q{a list-context read before +=});
round_trips(q{my $v=3; my $r=\$v; my $s = "$$r"; $$r -= 1; print "$s\n";},
    q{an interpolated read before -=});
round_trips(q{my $v=1; my $r=\$v; my $a = $$r; my $b = $$r++; print "$a $b\n";},
    q{a plain read before a postinc in value context});

# A named aggregate holding a stale-bound read is declared after the binding.
round_trips(q{my $v=1; my $r=\$v; my @h = ($$r); $$r = 2; print "$h[0] $v\n";},
    q{an array literal of one deref read before a plain store});
round_trips(q{my $v=1; my $r=\$v; my $o = $$r; my %h = (k => $o); $$r = 2; print "$h{k} $v\n";},
    q{a hash literal holding a copy of the read});
round_trips(q{my $v=1; my $r=\$v; my %h = (k => $$r, j => 2); $$r = 2; print "$h{k} $v\n";},
    q{a hash literal holding the read directly});
round_trips(q{my $v=1; my $r=\$v; my $o = $$r; my @h = ($o); $$r = 2; print "$h[0] $v\n";},
    q{an array literal holding a copy of the read});

# A guarded read is not hoisted above its guard: binding `$$r` ahead of
# `$r ? $$r : ...` dereferenced undef under strict refs.
round_trips(q{my $v=1; my $r; my $x=0; $x=1; my $a = $r ? $$r : "n"; $r=\$v; $$r=2; print "[$a] $v\n";},
    q{a ternary-guarded read of an undef reference});
round_trips(q{sub f { my $r=shift; my $z=0; my $zr=\$z; $z=1; my $x = ref $r ? $$r : $r; $z=2; return $x } print f(5), " ", f(\7), "\n";},
    q{a ref-guarded read in a sub, then an unrelated store});
round_trips(q{my $v=1; my $r; my $x=0; $x=1; my $a = defined($r) && $$r; $r=\$v; $$r=2; print "[$a] $v\n";},
    q{an &&-guarded read});
round_trips(q{my $v=1; my $r; my $x=0; $x=1; my $a = "u"; $a = $$r if $r; $r=\$v; $$r=2; print "[$a] $v\n";},
    q{a statement-modifier-guarded read});
round_trips(q{my $v=1; my $r; my $x=0; $x=1; my $a = "u"; unless (!$r) { $a = $$r; print "in\n" } $r=\$v; $$r=2; print "[$a] $v\n";},
    q{an unless-block-guarded read});
round_trips(q{my $v=1; my $r; my $x=0; $x=1; unless (!$r) { print $$r, "\n" } $r=\$v; $$r=2; print "$v\n";},
    q{a read printed inside an unless block});
round_trips(q{my $v=1; my $r; my $x=0; $x=1; my $a = $r // 0 ? $$r : "n"; $v = 2; print "[$a] $v\n";},
    q{a guarded read with a plain store after it});

# `.=` and `||=` through a ref are separate shapes (multiconcat, a
# short-circuit over sassign); they refuse rather than drop the store.
sub refuses ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, $name;
}
refuses('my $v="a"; my $r = \$v; $$r .= "x"; print "$v\n";',
    qr/GAP: multiconcat storing into a stacked destination that is not a package scalar/,
    '.= through a ref refuses');
refuses('my $v=0; my $r = \$v; $$r ||= 4; print "$v\n";',
    qr/GAP: `\|\|=` into something other than a lexical scalar/,
    '||= through a ref refuses');

done_testing;
