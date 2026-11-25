# ABOUTME: What runs before the main line and is not on the wire -- INIT/CHECK blocks, a followed module's
# ABOUTME: file-level effects or code beyond plain `our` data, an import storing elsewhere -- is named on the wire.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use JSON::PP;

# THE DEFECT (third final audit, N9, 22 probes): the wire starts the main
# line from a followed module's package data as it stood at CHECK. That is
# exact for plain data; a module's file lexicals (`my $priv = 5; sub priv {
# $priv }` printed nothing for 5), its prints at load, its stores into the
# program's package, its import's, an INIT block: none was on the wire and
# none was refused.

my $dir = tempdir( CLEANUP => 1 );
sub module ( $name, $src ) {
    open my $o, '>', "$dir/$name.pm" or die $!;
    print $o "package $name;\n$src\n1;\n";
    close $o;
}
module( 'MPlain',  'our $n = 1; our @l = (1, 2); our %h = (a => 1); sub get { $n }' );
module( 'MPriv',   'my $priv = 5; sub priv { $priv }' );
module( 'MPrint',  'print "loading "; our $v = 1; sub v { $v }' );
module( 'MMain',   '$main::g = 7; sub x { 1 }' );
module( 'MImp',    'sub import { $main::imp .= "i"; return }' );
module( 'MInit',   'our $n = 1; INIT { $n = 9 } sub get { $n }' );
module( 'MCode',   'our $n = 0; $n += $_ for 1 .. 3; sub get { $n }' );
module( 'MUnread', 'our $n = 0; $n += $_ for 1 .. 3; sub get { $n }' );
# (a store into a package the same file declares is the module's own:
# POSIX.pm sets %POSIX::... under `package POSIX::SigRt`)
module( 'MOwn',    'our %h; package MOwn::Sub; $MOwn::h{a} = 1; package MOwn; sub get { $h{a} }' );

my $n = 0;
sub compile ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o "use lib '$dir'; $src";
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null);
    return eval { JSON::PP->new->decode($json)->{start_up} } // '';
}

for my $case (
    [ 'use MPriv; print MPriv::priv(), "\n";',            qr/file-level code beyond plain `our` data \(MPriv: pad/ ],
    [ 'use MPrint; print "main\n";',                       qr/a followed module's file-level code \(MPrint: print\)/ ],
    [ 'our $g; use MMain; print defined $g ? $g : "u";',  qr/file-level code \(MMain: store-into-main\)/ ],
    [ 'our $imp; use MImp; print $imp // "u", "\n";',      qr/the import of a followed module \(MImp\) storing into another package/ ],
    [ 'use MInit; print MInit::get(), "\n";',              qr/a followed module's INIT block \(MInit\)/ ],
    [ 'INIT { print "i" } print "r\n";',                   qr/an INIT block of the program/ ],
    [ 'CHECK { print "c" } print "r\n";',                  qr/a CHECK block of the program/ ],
    [ 'use MCode; print MCode::get(), "\n";',              qr/file-level code beyond plain `our` data \(MCode: / ],
    [ 'use MPlain; BEGIN { print MPlain::get(), "\n" }',   qr/a BEGIN block of the program calling a followed module's sub \(MPlain::get\)/ ],
) {
    like compile( $case->[0] ), qr/\AGAP: .*$case->[1]/, "refused on the wire (start_up): $case->[0]";
}

# (plain data, and code in a module the program reads nothing of: as before)
for my $src (
    'use MPlain; print MPlain::get(), "@MPlain::l $MPlain::h{a}\n";',
    'use MUnread; print "x\n";',
    'use MOwn; print "x\n";',
    # (a class of the program calling its own import by hand reads no
    # followed module's: chalk's corpus adjacency-12)
    'use MPlain; package G; sub import { print "imp\n" } package main; G->import("t"); print MPlain::get(), "\n";',
) {
    is compile($src), '', "not refused: $src";
}

done_testing;
