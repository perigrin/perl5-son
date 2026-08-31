# ABOUTME: s/// on $_ resolves and rebinds it, like a match already does.
# ABOUTME: $_ is a package scalar in the scope map, not an unnameable target.
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
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# THE DEFECT. `s/a/X/` on $_ was refused as "s/// on an implicit $_ or
# package/global target", on the reading that the handler cannot NAME the
# target: subst keys on a pad targ, and $_ has none.
#
# It does not need one. $_ is the package scalar main::_, an ordinary SSA
# binding in the scope map, and the MATCH handler beside this one already
# resolves it that way -- keyed 'main::$_', sigil included, because `$_` and
# `@_` share a glob name. Reads of $_ have always worked (a match, a bare
# `print`, a builtin defaulting to it); only the WRITE was refused.
subtest 's/// on an implicit $_ translates' => sub {
    my ( $w, $err ) = translate( '$_ = "ab"; s/a/X/; print $_;', 'implicit' );
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/implicit \$_/, 'no $_ GAP';
};

subtest 's/// on an explicit $_ translates' => sub {
    # `$_ =~ s/a/X/` took the same refusal even though $_ is written out --
    # the message said "implicit", but the handler could not key EITHER form.
    my ( $w, $err ) = translate( '$_ = "ab"; $_ =~ s/a/X/; print $_;',
                                 'explicit' );
    ok $w, 'it translates' or diag($err), return;
    unlike $err, qr/implicit \$_/, 'no $_ GAP';
};

# THE REBIND IS THE POINT. A destructive s/// mutates its target, so the read
# after it must see the substituted value -- not the pre-subst binding. This is
# what the pad path does via $sim->define, and $_ needs the same.
subtest 'the read after s/// sees the substituted value' => sub {
    my ( $w, $err ) = translate( '$_ = "ab"; s/a/X/; print $_;', 'rebind' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($print) = grep { ( $_->{op} // '' ) eq 'Print' } $ns->@*;
    ok $print, 'the print is in the graph' or return;

    my $arg = $by{ ( $print->{inputs} // [] )->[0] // -1 };
    $arg = $by{ ( $arg->{inputs} // [] )->[0] // -1 }
        if $arg && ( $arg->{op} // '' ) eq 'Coerce';
    ok $arg, 'the print has a value' or return;
    is $arg->{op}, 'RegexSubst',
        'it reads the RegexSubst result, not the pre-subst binding';
};

# /r IS NON-DESTRUCTIVE and must NOT rebind: it yields a new string and leaves
# $_ alone. Without this a fix could rebind unconditionally and break it.
subtest 's///r on $_ does not rebind' => sub {
    my ( $w, $err ) = translate(
        '$_ = "ab"; my $t = s/a/X/r; print $_;', 'nondestruct' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($print) = grep { ( $_->{op} // '' ) eq 'Print' } $ns->@*;
    ok $print, 'the print is in the graph' or return;

    my $arg = $by{ ( $print->{inputs} // [] )->[0] // -1 };
    $arg = $by{ ( $arg->{inputs} // [] )->[0] // -1 }
        if $arg && ( $arg->{op} // '' ) eq 'Coerce';
    isnt( ( $arg->{op} // '' ), 'RegexSubst',
        '$_ still reads its own value, not the /r result' );
};

done_testing;
