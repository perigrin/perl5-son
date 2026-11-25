# ABOUTME: A followed module's package scalars, as its file-level code left them at `use` time, are put on
# ABOUTME: the wire as a BEGIN block run first; what that cannot say (aggregates, references) is refused.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# THE DEFECT (second final audit, class K9): `use ZUp; print "$ZUp::n"` --
# the module says `our $n = 1` -- printed an empty line. perl runs a used
# module's file at compile time and frees its code; the wire held the
# module's subs and nothing of the state its file left.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ( $src, $err = '2>&1' ) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o "use lib 't/lib'; $src";
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f $err);
}
sub begin_writes ($json) {
    my $w = JSON::PP->new->decode($json);
    my @b = grep { $_->{phase} eq 'BEGIN' } ( $w->{phase_blocks} // [] )->@*;
    return [] unless @b;
    my @n = $b[0]{nodes}->@*;
    my %by = map { $_->{id} => $_ } @n;
    return [ sort map {
        my ( $t, $v ) = map { $by{$_} } $_->{inputs}->@[ 0, 1 ];
        "$t->{fields}{package}::$t->{fields}{symbol}=" . ( $v->{fields}{value} // 'undef' )
    } grep { $_->{op} eq 'EntryWrite' } @n ];
}

{   my $json = compile( 'use K9::Mod; print "$K9::Mod::n $K9::Mod::s\n";', '2>/dev/null' );
    is begin_writes($json), [ 'K9::Mod::n=1', 'K9::Mod::s=a"b' ], 'the scalars the program reads, first';
}
{   my $json = compile( 'use K9::Mod; K9::Mod::bump(); print K9::Mod::get(), "\n";', '2>/dev/null' );
    is begin_writes($json), ['K9::Mod::n=1'], 'a scalar only a sub of the module reads';
}
like compile('use K9::Mod; print "@K9::Mod::l\n";'), qr/GAP: a followed module's package variable its file-level code set \(\@K9::Mod::l\)/, 'an aggregate: refused';
like compile('use K9::Mod; print "$K9::Mod::r->[0]\n";'), qr/GAP: a followed module's package variable its file-level code set \(\$K9::Mod::r\)/, 'a reference: refused';
like compile('use K9::Mod; BEGIN { $K9::Mod::n = 5 } print "$K9::Mod::n\n";'), qr/GAP: a followed module's package variable .* a BEGIN block of the program/, 'a BEGIN block that writes it: refused';
unlike compile('use K9::Mod; print defined $K9::Mod::u ? "d" : "u", "\n";'), qr/GAP/, 'an undef one: nothing to say';
done_testing;
