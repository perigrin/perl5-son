# ABOUTME: `\$a[i]` is the element at index i NOW: the reference reads its aggregate's memory and
# ABOUTME: stands where it is taken; a store through it is a store the aggregate's later reads see.
use 5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use Scalar::Util qw(refaddr);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub write_src ($src) {
    my $f = "$dir/p." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return $f;
}
sub run_perl ($src) {
    my $f = write_src($src);
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}
sub wire ($src) {
    my $f = write_src($src);
    my $j = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}
sub nodes ($w, $sub = 'main::__PROGRAM__') {
    my %n;
    my $walk; $walk = sub ($x) {
        if (ref $x eq 'HASH') { $n{ $x->{id} } = $x if defined $x->{op} && defined $x->{id} && !ref $x->{id}; $walk->($_) for values %$x }
        elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
    };
    $walk->($w->{methods}{$sub} // {});
    return \%n;
}
# the references to an element: a Ref over a Subscript
sub elem_refs ($n) {
    grep { $_->{op} eq 'Ref' && ( $n->{ $_->{inputs}[0] }{op} // '' ) eq 'Subscript' } values %$n;
}
sub is_memory ($n, $id) {
    my $x = $n->{$id} or return 0;
    return 1 if $x->{op} =~ /\A(?:MemStart|Call|Assign)\z/ || ( $x->{op} eq 'Phi' && $x->{fields}{memory} );
    return 0;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = wire($src);
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    is run_perl($out), $want, "$name: perl's answer"
        or diag "--- emitted ---\n$out--- want ---\n$want";
}

# THE ELEMENT IS THE ONE AT ITS INDEX WHEN THE REFERENCE IS TAKEN. Before, the
# reference read no memory: these two programs were one graph.
{
    my $before = nodes(wire(q{my @a = (1, 2, 3); my $r = \$a[0]; shift @a; print "$$r\n";}));
    my $after  = nodes(wire(q{my @a = (1, 2, 3); shift @a; my $r = \$a[0]; print "$$r\n";}));
    my ($rb) = elem_refs($before);
    my ($ra) = elem_refs($after);
    ok $rb && $ra, 'each takes a reference to an element' or last;
    ok scalar( $rb->{inputs}->@* ) == 1 && defined $rb->{mem_in}, q(the reference reads memory: its location, at a memory version);
    is $before->{ $rb->{mem_in} }{op}, 'MemStart', 'taken before the shift, it reads the memory before it';
    is $after->{ $ra->{mem_in} }{op} . '/' . ( $after->{ $ra->{mem_in} }{fields}{name} // '' ), 'Call/shift',
        'taken after the shift, it reads the memory the shift made';
    ok defined $rb->{control_in}, 'it stands where it is taken, on the control chain';
    my ($shift) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'shift' } values %$before;
    is $shift->{mem_in}, $rb->{id}, 'and the shift after it is ordered after it (the memory version it is)';
}
{
    my $n = nodes(wire(q{my %h = (k => 1); my $r = \$h{k}; delete $h{k}; print "$$r\n";}));
    my ($r) = elem_refs($n);
    ok $r && $r->{inputs}->@* == 1 && $n->{ $r->{mem_in} // -1 }{op} eq q(MemStart), 'a hash element too';
}
{
    my $n = nodes(wire(q{my @a = (1, 2); shift @a; my @r = \(@a); print ${$r[0]}, "\n";}));
    my ($r) = grep { $_->{op} eq 'Ref' && $_->{fields}{each} } values %$n;
    ok $r && $r->{inputs}->@* == 1 && is_memory($n, $r->{mem_in}), 'a reference to each element reads memory too';
}

# ONE THAT MAY DIE NAMES ITS SITE: `\$a[$i]` with $i before the start dies
# "Modification of non-creatable array value attempted, subscript -N at FILE
# line N.", its statement's -- the two fields an Unwind and a warn Call carry.
# One that cannot die (a hash's element, an index a constant not before the
# start, each element) names none.
{
    my $n = nodes(wire(qq{my \@a = (1, 2);\nmy \$i = -5;\n\$i++ if \@ARGV;\nmy \$r = \\\$a[\$i];\nprint "x\\n";\n}));
    my ($r) = elem_refs($n);
    ok $r, 'a reference to an element at an index not a constant' or last;
    is $r->{fields}{line}, 4, 'it names its statement\'s line';
    like $r->{fields}{file} // '', qr/\.pl\z/, 'and its file';
}
{
    my $n = nodes(wire(qq{my \@a = (1, 2);\nmy \$r = \\\$a[-5];\nprint "x\\n";\n}));
    my ($r) = elem_refs($n);
    is $r && $r->{fields}{line}, 2, 'an index a constant before the start: its line';
}
for my $src (q{my %h = (k => 1); my $r = \$h{k}; print "$$r\n";},
             q{my @a = (1, 2); my $r = \$a[1]; print "$$r\n";},
             q{my @a = (1, 2); my @r = \(@a); print ${$r[0]}, "\n";}) {
    my $n = nodes(wire($src));
    my @r = grep { $_->{op} eq 'Ref' } values %$n;
    ok @r && !grep({ defined $_->{fields}{line} } @r), "one that cannot die names no site: $src";
}

# IN AN EVAL'S BODY it stands on the body's chain, where it dies: the eval
# catches it there, so it does not mark the eval (eval_may_die is for a die
# the graph would drop). In a loop, at the index the loop counts.
{
    my $w = wire(q{my @a = (1, 2); my $i = -9; $i++ if @ARGV; eval { my $q = \$a[$i]; print "no\n"; 1 } or print "caught\n"; print "@a\n";});
    my $n = nodes($w);
    my ($r) = grep { $_->{op} eq 'Region' && defined $_->{fields}{eval_id} } values %$n;
    ok $r && !$r->{fields}{eval_may_die}, 'an eval whose body takes one is not marked as one that may die unseen';
}
round_trips(q{my @a = (1, 2); my $i = -9; $i++ if @ARGV; eval { my $q = \$a[$i]; print "no\n"; 1 } or print "caught: ", $@ =~ /\A(Modification of non-creatable array value attempted, subscript -9) at /, "\n"; print "@a\n";}, 'its die caught by an eval');
round_trips(q{my @a = (1, 2, 3); for my $i (0 .. 2) { my $r = \$a[$i]; $$r *= 10 } print "@a\n";}, 'at an index a loop counts');

# A STORE THROUGH IT IS A STORE TO THE AGGREGATE. Before, `print "@a"` folded to
# what @a was made with.
round_trips(q{my @a = (1, 2); my $r = \$a[0]; $$r = 5; print "@a\n";}, 'a store through an element reference');
round_trips(q{my @a = (1, 2); my $r = \$a[0]; $$r++; print "@a\n";}, 'an increment through it');
round_trips(q{my @a = (1, 2); my $r = \$a[1]; my $x = "x"; $$r .= $x; my $s = "@a"; print "$s\n";}, 'an append through it');
round_trips(q{my @a = (1, 2); my $r = \$a[0]; $$r = 5; print $a[0] + $a[1], "\n";}, 'element reads after a store through it');
round_trips(q{my %h = (k => 1, j => 2); my $r = \$h{k}; $$r = 5; print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";}, 'a hash element');
round_trips(q{my %h = (k => 1); my $r = \$h{k}; $$r++; print "$h{k}\n";}, 'an increment through a hash element reference');
round_trips(q{my @a = (1, 2, 3); my $r = \$a[0]; shift @a; $$r = 9; print "@a $$r\n";}, 'a shift after it: the element shifted off');
round_trips(q{my @a = (1, 2, 3); shift @a; my $r = \$a[0]; $$r = 9; print "@a $$r\n";}, 'a shift before it: the element now first');
round_trips(q{my @a = (1, 2); for my $i (1, 2) { print "@a\n"; my $r = \$a[0]; $$r += $i }}, 'in a loop, read before it is taken');
round_trips(q{my %h; my $r = \$h{x}; print exists $h{x} ? "yes\n" : "no\n";}, 'taking it makes the hash element');
# A COPY OF A `my` HASH THE PROGRAM WRITES (an element store, a reference to
# an element) is of its pairs where it is made: bound as the hash's literal,
# `my %g = %h` was %h itself, and a later store to %h showed through %g.
round_trips(q{my %h = (a => 1); my %g = %h; $h{a} = 5; print "$g{a} $h{a}\n";}, 'a copy of a written hash, then a store');
round_trips(q{my %h = (a => 1); my $r = \$h{a}; my %g = %h; $$r = 5; print "$g{a} $h{a}\n";}, 'a copy of a hash an element reference is taken of');
round_trips(q{my %h = (a => 1); my %g = %h; print "$g{a}\n";}, 'a copy of a hash nothing writes');
round_trips(q{my @a = (1); my $r = \$a[3]; print scalar(@a), "\n";}, 'taking it makes the array element');
round_trips(q{my @a = (1, 2, 3); my ($p, $q) = \($a[0], $a[1]); shift @a; $$q = 5; print "@a\n";}, 'references to elements named in a list');
round_trips(q{my @a = (1, 2); my @r = \(@a); ${$r[1]} = 5; print "@a\n";}, 'a reference to each element');

# A SLICE'S REFERENCES, one per element, have no node: refused, not one reference.
for my $src (q{my @a = (1, 2, 3); my @r = \(@a[0, 1]); $$_ *= 10 for @r; print "@a\n";},
             q{my %h = (a => 1, b => 2); my ($p, $q) = \(@h{qw(a b)}); $$q = 5; print "$h{b}\n";}) {
    wire($src);
    like do { open my $e, '<', "$dir/err"; local $/; <$e> }, qr/GAP: a reference to each element of a slice/, 'a reference to each element of a slice is refused';
}

done_testing;
