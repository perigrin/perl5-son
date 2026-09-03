# ABOUTME: `undef @a` / `undef %h` on a PACKAGE aggregate empties it, like the lexical form.
# ABOUTME: The lexical arm keys on a pad targ; a package variable has none.
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

# AN AGGREGATE IS EMPTIED, NOT REBOUND. `undef @a` and `@a = ()` are the same
# operation -- both leave zero elements -- and neither is `@a = undef`, which
# leaves ONE undef element. The lexical form already lowers by binding the slot
# to an empty ArrayLiteral/HashLiteral.
#
# THE PACKAGE FORM REFUSED because the lexical arm keys on `$kid->targ`, a pad
# index a package variable does not have. Its container arrives as rv2av/rv2hv
# rather than padav/padhv, so it fell through to the GAP -- three of perl's own
# t/comp files (parser.t, package.t, form_scope.t), each losing its whole
# __PROGRAM__.
#
# Measured on 5.42.0: `our @a=(1,2); undef @a; scalar(@a)` is 0.
subtest 'undef on a package array empties it' => sub {
    my ($n, $err) = wire('our @a=(1,2); undef @a; print scalar(@a);', 'pkg_array');
    unlike $err, qr/GAP|INTERNAL/, 'it translates';
    my @lit = grep { $_->{op} eq 'ArrayLiteral' && !(($_->{inputs} // [])->@*) } $n->@*;
    ok scalar(@lit), 'an EMPTY ArrayLiteral is built -- the `@a = ()` shape';
};

# THE HASH FORM TRANSLATES, but its emptying is not yet OBSERVABLE by a later
# read, and that is a separate pre-existing defect rather than something this
# change introduces. Measured: `keys %h` compiles to rv2hv with OPf_MOD set
# (sKM/KEYS), so the package-aggregate READ path takes its is_target branch and
# builds a FRESH EntryDef, discarding whatever the scope map holds. The bind
# this arm makes is correct and correctly keyed (main::%h, verified); nothing
# downstream consults it.
#
# ASSERTED AS THE CURRENT STATE, not as success: the refusal is gone, and when
# the read path stops rebuilding over a live binding this subtest fails and
# someone comes back to strengthen it.
subtest 'undef on a package hash translates (emptying not yet observable)' => sub {
    my ($n, $err) = wire('our %h=(a=>1); undef %h; print scalar(keys %h);', 'pkg_hash');
    unlike $err, qr/GAP|INTERNAL/, 'it translates rather than refusing';
    my @lit = grep { $_->{op} eq 'HashLiteral' && !(($_->{inputs} // [])->@*) } $n->@*;
    is scalar(@lit), 0,
        'the empty HashLiteral is NOT yet reachable from the later keys read'
        . ' -- delete this expectation when the read path stops rebuilding';
};

# THE LEXICAL FORMS MUST KEEP WORKING -- they already did, and a fix that
# reroutes the aggregate arm could take them with it.
subtest 'lexical aggregates are unaffected' => sub {
    my (undef, $e1) = wire('my @a=(1,2); undef @a; print scalar(@a);', 'lex_array');
    unlike $e1, qr/GAP|INTERNAL/, 'my @a still translates';
    my (undef, $e2) = wire('my %h=(a=>1); undef %h; print scalar(keys %h);', 'lex_hash');
    unlike $e2, qr/GAP|INTERNAL/, 'my %h still translates';
};

# AND THE PACKAGE SCALAR, which took a different arm already and must not be
# disturbed by a change to the aggregate one.
subtest 'a package scalar still rebinds to undef' => sub {
    my (undef, $err) = wire('our $x=5; undef $x; print defined($x)?1:0;', 'pkg_scalar');
    unlike $err, qr/GAP|INTERNAL/, 'our $x still translates';
};

# `undef *GLOB` IS NOT THE SAME OPERATION -- it clears a symbol-table slot
# (code, scalar, array, hash and handle at once), not a container's elements.
# It stays refused rather than being lowered as an empty aggregate.
subtest 'undef on a glob refuses by name' => sub {
    my (undef, $err) = wire('undef *STDERR; print "g";', 'glob');
    unlike $err, qr/INTERNAL/, 'no crash';
    like $err, qr/GAP/, 'it refuses';
};

done_testing;
