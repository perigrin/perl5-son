# ABOUTME: A block eval's Region names where the protected body BEGAN.
# ABOUTME: Without it the statements it protects cannot be told from those before.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    my $d = eval { JSON::PP->new->decode($j) } or return undef;
    return $d->{methods}{'main::__PROGRAM__'};
}

# THE JOIN WAS RECORDED AND THE ENTRY WAS NOT. Measured on
# `our $g=0; our $h=0; $h=5; if (eval { $g = 1; 1 }) {...}`:
#
#     Region(23) in=[12]
#     chain back: EntryWrite 12, 11, 10, 9, Start
#
# Four stores chain to Start and only the LAST is inside the eval -- the others
# are `our $g=0`, `our $h=0` and `$h=5`. Nothing distinguished them, so a
# consumer could not delimit the protected body.
#
# THE ENTRY IS AVAILABLE WHERE THE REGION IS BUILT: `$sim->control` before the
# body walk IS the boundary. Recording it costs nothing and is the difference
# between a block eval being spellable and not.
subtest 'the Region names the eval entry' => sub {
    my $g = graph_of(<<'SRC');
our $g = 0;
our $h = 0;
$h = 5;
if (eval { $g = 1; 1 }) { print "ok\n" } else { print "died\n" }
SRC
    ok $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;

    # A single-input Region with a Phi over it whose second input is the undef
    # -- the eval join, in either form.
    my ($region) = grep {
        my $r = $_;
        ($r->{op} // '') eq 'Region' && ($r->{inputs} // [])->@* == 1
            && grep {
                   ($_->{op} // '') eq 'Phi'
                && ((($_->{fields} // {})->{region} // -1) == $r->{id})
                && ((($by{ ($_->{inputs} // [])->[1] // -1 }{fields} // {})
                     ->{const_type} // '') eq 'undef')
               } $g->{nodes}->@*;
    } $g->{nodes}->@*;
    ok $region, 'the eval join is present' or return;

    my $entry = ($region->{fields} // {})->{eval_entry};
    ok defined $entry, 'and it names the eval entry';
    return unless defined $entry;

    # THE ENTRY MUST BE BEFORE THE JOIN AND AFTER THE PRECEDING STATEMENTS.
    # Walking back from the join must reach it, and the stores outside the
    # eval must be on the far side of it.
    my @back;
    my $cur = ($region->{inputs} // [])->[0];
    while (defined $cur && @back < 20) {
        push @back, $cur;
        $cur = $by{$cur} ? $by{$cur}{control_in} : undef;
    }
    ok scalar(grep { $_ == $entry } @back),
        '... and the entry is on the chain behind the join'
        or diag "chain: @back  entry: $entry";

    # THE BODY IS WHAT LIES BETWEEN THEM, and it must be exactly the one store
    # the eval protects -- not the three before it.
    my @body;
    for my $id (@back) {
        last if $id == $entry;
        push @body, $id;
    }
    is scalar(@body), 1,
        'and the body between entry and join is one statement'
        or diag "body: @body";
};

# A STRING EVAL NEEDS NO ENTRY -- its Region's input IS the eval, one node, so
# there is nothing to delimit. It must not grow a spurious one.
subtest 'a string eval needs no entry' => sub {
    my $g = graph_of('my $v = eval "1+1"; print "[$v]\n";');
    ok $g, 'it translates' or return;

    my ($coerce) = grep { ($_->{op} // '') eq 'Coerce'
                       && ((($_->{fields} // {})->{to_repr} // '') eq 'Code') }
                   $g->{nodes}->@*;
    ok $coerce, 'the string eval is a Coerce to Code';
};

done_testing;
