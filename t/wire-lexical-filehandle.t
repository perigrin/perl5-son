# ABOUTME: A lexical filehandle is a GlobRef, not a hole -- open defines it as one.
# ABOUTME: `open(my $T, ...)` then <$T>/close($T) left $T's PadAccess Unknown.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub nodes_of ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    return [ map { { $_->%*, ($_->{fields} // {})->%* } }
             ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* ];
}

my $SRC = 'open(my $T, "<", "/dev/null") or die; my $l = <$T>; close($T);';

# PERL SETTLES THIS, it is not a judgement call. After `open(my $T, ...)`,
# measured on 5.42.0:
#
#     ref($T)     GLOB        so the lattice type is GlobRef
#     reftype($T) GLOB
#     blessed     no          not an object, so not IO
#
# AND OPEN DEFINES IT EVEN WHEN THE OPEN FAILS:
#
#     open($T, "<", "/nonexistent")   returns false, $T is defined, ref GLOB
#
# which is what makes GlobRef unconditional rather than join(GlobRef, Undef).
# The handle is a real value at every point after the open, whatever the
# open's own boolean says.
subtest 'a lexical filehandle is a GlobRef, not a hole' => sub {
    my $nodes = nodes_of($SRC, 'lexfh');
    my ($pad) = grep { $_->{op} eq 'PadAccess' && ($_->{varname} // '') eq '$T' } $nodes->@*;
    ok defined $pad, 'the $T pad access exists' or return;
    isnt $pad->{stamp}, 'Unknown', 'the handle is not a hole';
    is $pad->{stamp}, 'GlobRef', 'perl says ref($T) is GLOB, so the stamp is GlobRef';
};

# THE HANDLE REACHES ALL THREE BUILTINS and each must see the same type. A fix
# that only stamps the open call site would leave close/readline reading an
# Unknown operand.
subtest 'every builtin taking the handle sees a typed operand' => sub {
    my $nodes = nodes_of($SRC, 'lexfh_ops');
    my %byid = map { $_->{id} => $_ } $nodes->@*;
    my @calls = grep { $_->{op} eq 'Call'
                       && ($_->{name} // '') =~ /^(open|close|readline)$/ } $nodes->@*;
    ok scalar(@calls) >= 2, 'the handle-taking calls exist' or return;
    my $checked = 0;
    for my $c (@calls) {
        my $operand = $byid{ ($c->{inputs} // [])->[0] // -1 } or next;
        next unless ($operand->{varname} // '') eq '$T';
        $checked++;
        isnt $operand->{stamp}, 'Unknown',
            "$c->{name}: its handle operand is typed";
    }
    ok $checked >= 2, 'the handle operand was actually inspected, not skipped';
};

# A PLAIN LEXICAL IS UNTOUCHED. The rule must key on being an open TARGET, not
# on being a pad slot -- otherwise every `my $x` becomes a filehandle.
subtest 'an ordinary lexical is not called a filehandle' => sub {
    my $nodes = nodes_of('my $x = 5; my $y = $x + 1; print $y;', 'plainlex');
    my @globs = grep { ($_->{stamp} // '') eq 'GlobRef' } $nodes->@*;
    is scalar(@globs), 0, 'no ordinary lexical is stamped GlobRef';
};

# A BAREWORD HANDLE IS A GLOB, NOT A GlobRef, and not the string "FOO". perl
# draws the distinction and the lattice keeps it:
#
#     ref(*FOO)   not a reference at all -- a Glob
#     ref(\*FOO)  GLOB                   -- a GlobRef
#     ref($lex)   GLOB                   -- a GlobRef
#
# join(Glob, GlobRef) is Unknown, so ONE operand requirement cannot cover both
# spellings. Declaring `open => operands => ['GlobRef']` made the coercion pass
# wrap the bareword in Coerce(Glob -> GlobRef) -- fabricating a reference from
# a glob that is not one, which is why each spelling is stamped at its source.
subtest 'a bareword handle is a Glob, and gains no coercion' => sub {
    my $nodes = nodes_of('open(FOO, ">", "/dev/null") or die; close FOO;', 'bareword');
    my ($h) = grep { $_->{op} eq 'Constant' && ($_->{value} // '') eq 'FOO' } $nodes->@*;
    ok defined $h, 'the handle constant exists' or return;
    isnt $h->{stamp}, 'Str', 'the handle is not the string "FOO"';
    is $h->{stamp}, 'Glob', 'a bareword handle is a Glob';

    my @coerced = grep { $_->{op} eq 'Coerce'
                         && ($_->{to_repr} // '') eq 'GlobRef' } $nodes->@*;
    is scalar(@coerced), 0,
        'a glob is not coerced into a reference it is not';
};

done_testing;
