# ABOUTME: `$$r = 5` stores through a reference; the referent must see it, so
# ABOUTME: the write is an Assign over the deref on the memory chain.

use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $out  = qx{$PERL $file 2>/dev/null};
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub prog ( $w ) { return ( ( $w // {} )->{methods}{'main::__PROGRAM__'}{nodes} // [] ) }

# THE WRITE MUST REACH THE REFERENT. `$$r = 5` is not a rebinding of $r -- it
# stores into the location $r points at, and every later read of that location
# sees it:
#
#     my $v = 1; my $r = \$v; $$r = 5;  ->  $v is 5
#     my $q2 = $q;            $$q2 = 20;    ->  the ORIGINAL referent is 20
#
# The machinery already exists: taking a reference DEMOTES the variable, so its
# reads carry a memory version and its writes are Assign stores on the memory
# chain. A deref write is the symmetric store -- an Assign whose target is the
# dereferenced location rather than a pad slot.

subtest 'a write through a reference is a store, not a rebind' => sub {
    my ( $out, $w, $err ) = translate(
        'my $v = 1; my $r = \$v; $$r = 5; print $v;', 'deref-write' );
    is $out, '5', 'perl updates the referent' or return;

    unlike $err, qr/GAP/, 'it does not GAP' or diag($err);
    my $ns = prog($w);
    ok scalar($ns->@*), 'the program graph is present' or return;

    my %by = map { $_->{id} => $_ } $ns->@*;

    # An Assign whose target resolves through a PostfixDeref is the store.
    # A rebind of $r would target the pad instead, and the referent would
    # never see the value.
    my @stores = grep {
        my $n = $_;
        ( $n->{op} // '' ) eq 'Assign'
            && grep {
                   my $in = $by{$_};
                   $in && ( $in->{op} // '' ) eq 'PostfixDeref'
               } ( $n->{inputs} // [] )->@*
    } $ns->@*;
    ok scalar(@stores), 'an Assign stores through the dereference';
};

# A DEREF READ IS UNCHANGED. A fix that made every rv2sv a store would be a
# regression dressed as symmetry.
subtest 'a deref read is still a read' => sub {
    my ( $out, $w, $err ) = translate(
        'my $v = 7; my $r = \$v; print $$r;', 'deref-read' );
    is $out, '7', 'perl reads through the ref' or return;
    unlike $err, qr/GAP/, 'it does not GAP' or diag($err);

    my $ns = prog($w);
    my ($d) = grep { ( $_->{op} // '' ) eq 'PostfixDeref' } $ns->@*;
    ok $d, 'a PostfixDeref exists';
};

# THE ALIAS CASE, which is the whole reason a value binding cannot express
# this: a second name for the same reference must write the same location.
subtest 'a write through an aliased reference reaches the referent' => sub {
    my ( $out, undef, $err ) = translate(
        'my $w = 10; my $q = \$w; my $q2 = $q; $$q2 = 20; print $w;',
        'deref-alias' );
    is $out, '20', 'perl updates through the alias' or return;
    unlike $err, qr/GAP/, 'it does not GAP' or diag($err);
};

done_testing;
