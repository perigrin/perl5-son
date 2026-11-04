# ABOUTME: A string eval shares its frame and can write any lexical in scope unseen, so it
# ABOUTME: refuses whenever one is; PadWalker calls refuse the same way, at the same site.

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

# The producer's graph and everything it said on stderr.
sub produce ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    open my $eh, '<', "$dir/err" or die $!;
    my $err = do { local $/; <$eh> } =~ s/^\S+ syntax OK\n//mr;
    return (eval { JSON::PP->new->decode($j) }, $err);
}

my $GAP = qr/GAP: a string eval with a lexical in scope/;

sub refuses ($src, $name, $why = $GAP) {
    my ($data, $err) = produce($src);
    like $err, $why, "$name: refuses, naming why";
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ($data, $err) = produce($src);
    is $err, '', "$name: the producer says nothing";
    my $d = SoN::Deparse->new;
    my $out = $data ? $d->render($data) : undef;
    unless (defined $out) { fail "$name: renders"; diag $d->gap // $err; return }
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
}

# The read after the eval was the binding from before it: perl printed i=1,
# the emitted program i=0, and nothing refused.
refuses(q{my $i = 0; eval q{$i = 1}; print "i=$i\n";},
    'an eval writing a file lexical');
refuses(q{sub f { my $i = 0; eval q{$i = 1}; return $i } print f(), "\n";},
    'an eval writing a sub lexical');
refuses(q{sub f { my @a = (1); eval q{push @a, 2}; return scalar @a } print f(), "\n";},
    'an eval pushing onto a lexical array');
refuses(q{our $p = 0; eval q{$p = 1}; print "p=$p\n";},
    'an eval writing through an our alias');
refuses(q{my $i = 0; sub f { $i; eval q{$i = 1} } f(); print "i=$i\n";},
    'an eval writing a lexical the sub closes over');
refuses(q{my $i = 0; my $c = "\$i = 1"; eval $c; print "i=$i\n";},
    'an eval of a computed string');

# NO LEXICAL, NOTHING TO HIDE: the eval stays lowered, as do package variables
# it writes (the program-wide demotion already treats them as written).
round_trips(q{sub h { return eval "1+1" } print h(), "\n";},
    'an eval with no lexical in scope still lowers');
round_trips(q{$main::p = 0; eval q{$main::p = 1}; print "p=$main::p\n";},
    'an eval writing a package scalar still lowers');

# PadWalker reads and rewrites lexicals -- the caller's too -- from outside
# the graph, which is the eval's hazard by another name.
my $PW = qr/GAP: PadWalker::\w+ reads or writes lexicals the graph cannot see/;
refuses(q{use PadWalker qw(peek_my); sub f { my $i = 0; ${ peek_my(0)->{'$i'} } = 1; return $i } print f(), "\n";},
    'PadWalker::peek_my', $PW);
refuses(q{use PadWalker (); sub f { my $i = 0; my $h = PadWalker::peek_my(0); ${ $h->{'$i'} } = 1; return $i } print f(), "\n";},
    'PadWalker::peek_my by its full name', $PW);

done_testing;
