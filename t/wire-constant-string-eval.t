# ABOUTME: An eval of a constant string is compiled where B::SoN runs: a body
# ABOUTME: the program calls, sharing the lexicals it names by name.
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
    print {$fh} "$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=-q,SoN,json $file 2>$dir/$name.err};
    my $err = do { local (@ARGV, $/) = ("$dir/$name.err"); <> } // '';
    return ( eval { JSON::PP->new->decode($out) }, $err );
}

sub nodes ($w, $m) { ( $w->{methods}{$m}{nodes} // [] )->@* }

# `my $i = 0; eval q{$i = 1}; print $i` -- perl prints 1. The string is known
# when B::SoN runs, so its code is too: a body, called where the eval is.
{
    my ($w, $err) = wire(q{my $i = 0; eval q{$i = 1}; print "i=$i\n";}, 'write');
    ok($w && $w->{methods}{'main::__PROGRAM__'}, 'a constant eval: the program has a graph') or diag $err;
    my ($call) = grep { $_->{op} eq 'Call' && ( $_->{fields}{dispatch_kind} // '' ) eq 'direct' } nodes($w, 'main::__PROGRAM__');
    ok($call, 'the eval is a direct call');
    my $body = $call ? $call->{fields}{name} : '';
    ok(exists $w->{methods}{$body}, "its body is a graph ($body)");
    ok(( grep { $_->{op} eq 'PadAccess' && $_->{fields}{shared} && $_->{fields}{symbol} eq 'i' } nodes($w, $body) ),
        'the body writes $i, shared by name');
    ok(( grep { $_->{op} eq 'PadAccess' && $_->{fields}{shared} && $_->{fields}{symbol} eq 'i' } nodes($w, 'main::__PROGRAM__') ),
        'the program keeps $i shared');
}

# Its value is the body's: `my $r = eval q{2 * 3}` is 6.
{
    my ($w, $err) = wire(q{my $r = eval q{2 * 3}; print "$r\n";}, 'value');
    my ($call) = grep { $_->{op} eq 'Call' && ( $_->{fields}{dispatch_kind} // '' ) eq 'direct' } nodes($w, 'main::__PROGRAM__');
    ok($call, 'a constant eval\'s value: a direct call') or diag $err;
}

# A STRING MADE AT RUNTIME is code no one has seen: refused by name.
{
    my ($w, $err) = wire(q{my $n = $ENV{X} // 2; my $r = eval "$n + 1"; print "$r\n";}, 'runtime');
    like($err, qr/GAP: an eval of a string made at runtime/, 'a runtime string: refused by name');
}

# A BODY THAT CAN DIE is caught by the eval -- perl sets $@ and yields undef.
# Not yet lowered: refused by name, not left to exit.
{
    my ($w, $err) = wire(q{my $n = 9; my $r = eval q{die "no\n" if $n > 5; $n * 2}; print defined $r ? "d" : "u", "\n";}, 'dies');
    like($err, qr/GAP: an eval of a constant string whose code can die/, 'a body that can die: refused by name');
    ($w, $err) = wire(q{my $n = 0; my $r = eval q{6 / $n}; print defined $r ? "d" : "u", "\n";}, 'divides');
    like($err, qr/GAP: an eval of a constant string whose code can die/, 'a division in the body: refused by name');
}

done_testing;
