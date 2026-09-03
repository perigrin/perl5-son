# ABOUTME: A capturing anon sub gets cells: MakeCell outside, CellParam/CellRead inside.
# ABOUTME: A capture is a shared mutable cell, not a snapshot of a value.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return ($w, $err);
}

sub nodes_of ($w, $meth) {
    return [ map { { $_->%*, ($_->{fields} // {})->%* } }
             ($w->{methods}{$meth} ? $w->{methods}{$meth}{nodes}->@* : ()) ];
}

# A CAPTURE IS A SHARED MUTABLE CELL, not a value. Measured on 5.42.0:
#
#     my $n=5; my $c = sub { $n }; $n = 99;    $c->() is 99   the VARIABLE
#     my $set = sub { $n = shift }; $set->(42) outer $n is 42 it WRITES
#     my $c=0; $inc->(); $inc->();             $rd->() is 2   ONE cell shared
#
# So the value cannot ride on AnonSub's inputs -- that gives each closure a
# snapshot, right for the read-only case and wrong for all three above. The
# cell does, and its contract is chalk's (docs/samples/closure-cells.json):
#
#     MakeCell(init, memory)          -> a cell reference
#     CellRead(cell, memory)          -> the value
#     CellWrite(cell, value, memory)  -> new memory version
subtest 'a read-only capture builds a cell' => sub {
    my ($w, $err) = wire('my $n = 5; my $g = sub { $n + 1 }; print $g->();', 'ro');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    ok scalar(grep { $_->{op} eq 'MakeCell' } $prog->@*),
        'a MakeCell is built in the enclosing scope';
};

# THE BODY READS THROUGH THE CELL. A CellParam names the arriving cell and a
# CellRead takes its value -- so a later outer write is observable, which a
# baked-in constant would not be.
subtest 'the body reads through a CellParam' => sub {
    my ($w, $err) = wire('my $n = 5; my $g = sub { $n + 1 }; print $g->();', 'ro_body');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my ($body) = grep { /__ANON__/ } keys $w->{methods}->%*;
    ok defined $body, 'the body graph exists' or return;
    my $b = nodes_of($w, $body);
    ok scalar(grep { $_->{op} eq 'CellParam' } $b->@*), 'a CellParam names the cell';
    ok scalar(grep { $_->{op} eq 'CellRead' } $b->@*),  'and a CellRead takes its value';
};

# THE CELL IS AN INPUT TO AnonSub, which is what lets two closures share one.
subtest 'the AnonSub takes the cell as an input' => sub {
    my ($w, $err) = wire('my $n = 5; my $g = sub { $n + 1 }; print $g->();', 'ro_input');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    my %byid = map { $_->{id} => $_ } $prog->@*;
    my ($anon) = grep { $_->{op} eq 'AnonSub' } $prog->@*;
    ok defined $anon, 'the AnonSub exists' or return;
    my @in = map { $byid{$_} } ($anon->{inputs} // [])->@*;
    ok scalar(grep { ($_->{op} // '') eq 'MakeCell' } @in),
        'a MakeCell is among its inputs';
};

# SHARING: two closures over ONE variable take the SAME MakeCell node. This is
# the property a per-closure snapshot design gets wrong.
subtest 'two closures over one variable share one cell' => sub {
    my ($w, $err) = wire(
        'my $c = 0; my $inc = sub { $c = $c + 1 }; my $rd = sub { $c };'
        . ' print $inc->(), $rd->();', 'shared');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    my @anons = grep { $_->{op} eq 'AnonSub' } $prog->@*;
    is scalar(@anons), 2, 'two AnonSubs' or return;
    my %cells;
    for my $a (@anons) { $cells{$_}++ for ($a->{inputs} // [])->@* }
    my @shared = grep { $cells{$_} == 2 } keys %cells;
    ok scalar(@shared), 'both AnonSubs take the SAME cell node';
};

# captured_written IS DERIVABLE, and the naive rule is wrong: `$c = $c + 1`
# compiles to a TARGMY add with NO sassign and NO OPf_MOD, so a flag test
# reports "read-only" for the canonical mutation case.
subtest 'a written capture is marked written' => sub {
    my ($w, $err) = wire('my $c = 0; my $inc = sub { $c = $c + 1 }; print $inc->();', 'written');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    my ($mc) = grep { $_->{op} eq 'MakeCell' } $prog->@*;
    ok defined $mc, 'the MakeCell exists' or return;
    ok $mc->{captured_written}, 'captured_written is true for a TARGMY write';
};

subtest 'a read-only capture is marked not written' => sub {
    my ($w, $err) = wire('my $n = 5; my $g = sub { $n + 1 }; print $g->();', 'ro_flag');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    my ($mc) = grep { $_->{op} eq 'MakeCell' } $prog->@*;
    ok defined $mc, 'the MakeCell exists' or return;
    ok !$mc->{captured_written}, 'captured_written is false for a pure read';
};

# A NON-CAPTURING anon sub must not grow a cell -- it already lowered and its
# body needs nothing from the enclosing scope.
subtest 'a non-capturing anon sub gets no cell' => sub {
    my ($w, $err) = wire('my $c = sub { 42 }; print $c->();', 'noncap');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    my $prog = nodes_of($w, 'main::__PROGRAM__');
    is scalar(grep { $_->{op} eq 'MakeCell' } $prog->@*), 0, 'no MakeCell';
};

done_testing;
