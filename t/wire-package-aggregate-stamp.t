# ABOUTME: A package array/hash EntryDef carries Array/Hash -- its sigil says so.
# ABOUTME: Unstamped, _is_aggregate_node could not recognise it as iterable.
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
    my @n = $w ? (map { { $_->%*, ($_->{fields} // {})->%* } }
                  ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*) : ();
    return (\@n, $err);
}

# THE SIGIL ALREADY SAYS WHAT IT IS. A package aggregate is built as
# EntryDef(sigil => '@' or '%') with NO stamp, so `_is_aggregate_node` -- which
# reads the stamp -- could not recognise it, and `for (@pkg)` refused with
# "unrecognized bounds shape". The LEXICAL form pushes a padav that is stamped,
# which is why only the package spelling failed.
#
# perl's own t/comp/require.t hits it:
#     push @files_to_delete, "$_->[0].pm" for @module_true_tests;
subtest 'a package array is iterable' => sub {
    my (undef, $err) = wire('our @s=(1,2); print $_ for @s;', 'pkg_for');
    unlike $err, qr/GAP|INTERNAL/, 'foreach over a package array translates';
};

# AN UNBOUND package aggregate is where the EntryDef survives -- a bound one
# folds to an ArrayLiteral, so `our @s=(1,2)` never produces the node this
# subtest is about. My first draft used the bound form and passed VACUOUSLY,
# finding no EntryDef and returning early.
subtest 'the package array EntryDef is stamped Array' => sub {
    my ($n, $err) = wire('print scalar(@main::unbound);', 'pkg_stamp');
    my ($e) = grep { $_->{op} eq 'EntryDef' && ($_->{sigil} // '') eq '@' } $n->@*;
    ok defined $e, 'the EntryDef exists' or return;
    is $e->{stamp}, 'Array', 'and its sigil-derived stamp is Array';
};

subtest 'a package hash EntryDef is stamped Hash' => sub {
    my ($n, $err) = wire('print scalar(keys %main::unbound_h);', 'pkg_hash_stamp');
    my ($e) = grep { $_->{op} eq 'EntryDef' && ($_->{sigil} // '') eq '%' } $n->@*;
    ok defined $e, 'the EntryDef exists' or return;
    is $e->{stamp}, 'Hash', 'and its sigil-derived stamp is Hash';
};

# A PACKAGE SCALAR MUST NOT BE SWEPT UP. Its EntryDef carries sigil '$' and is
# not an aggregate; stamping every EntryDef Array would make `for ($x)` iterate
# a scalar.
subtest 'a package scalar is not stamped as an aggregate' => sub {
    my ($n, $err) = wire('print $main::unbound_s;', 'pkg_scalar_stamp');
    my ($e) = grep { $_->{op} eq 'EntryDef' && ($_->{sigil} // '') eq '$' } $n->@*;
    ok defined $e, 'the scalar EntryDef exists' or return;
    isnt +($e->{stamp} // ''), 'Array', 'it is not an Array';
    isnt +($e->{stamp} // ''), 'Hash',  'nor a Hash';
};

# THE LEXICAL FORM already worked and must keep working.
subtest 'a lexical array is still iterable' => sub {
    my (undef, $err) = wire('my @s=(1,2); print $_ for @s;', 'lex_for');
    unlike $err, qr/GAP|INTERNAL/, 'foreach over a lexical array translates';
};

done_testing;
