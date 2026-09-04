# ABOUTME: Observed-type corpus for the AGGREGATE MUTATION family.
# ABOUTME: The half pvm's precision corpus does not cover -- it has no memory model.
use v5.36;
no warnings;
require './t/oracle/observe_types.pl';

# THE MUTATION FAMILY. Every case here was a SILENT wrong answer in emitted IR
# at some point this session, not a refusal -- the class a coverage number
# cannot see. pvm's precision corpus covers literals, arithmetic, element
# access and sub returns, and has no mutation at all.

# --- whole-aggregate reads AFTER a mutation -------------------------------
my @sh = (1,2,3); shift @sh;
::__observe(__LINE__, 'count_after_shift', scalar(@sh));

my @pu = (1,2,3); push @pu, 4;
::__observe(__LINE__, 'count_after_push', scalar(@pu));

my @sp = (1,2,3); splice(@sp, 1, 1);
::__observe(__LINE__, 'count_after_splice', scalar(@sp));

# --- the RETURN VALUES of the mutators themselves -------------------------
my @rp = (1,2);
::__observe(__LINE__, 'push_returns', push(@rp, 3, 4));

my @ru;
::__observe(__LINE__, 'unshift_returns', unshift(@ru, 9));

my @rs = (1,2,3);
my @removed = splice(@rs, 1, 1);
::__observe(__LINE__, 'splice_returns_element', $removed[0]);

my @rsh = (10,20);
::__observe(__LINE__, 'shift_returns_element', shift(@rsh));

# --- the ALIASING write-back ----------------------------------------------
my @al = (1,2,3);
for my $x (@al) { $x = $x * 10 }
::__observe(__LINE__, 'element_after_alias_write', $al[1]);

my $sc = "axb";
foreach ($sc) { s/x/y/ }
::__observe(__LINE__, 'scalar_after_alias_subst', $sc);

# --- scalar context, the shape whose `scalar` op perl folds away ----------
sub trailing_count { my @a = (1,2,3); scalar @a }
::__observe(__LINE__, 'trailing_scalar_read', trailing_count());

my @asn = (1,2,3);
my $n = @asn;
::__observe(__LINE__, 'array_in_scalar_assign', $n);

my %h = (a=>1, b=>2);
my $hn = %h;
::__observe(__LINE__, 'hash_in_scalar_assign', $hn);

::__observe(__LINE__, 'last_index', $#asn);

# --- builtins whose result type perl defines ------------------------------
open my $null, '>', '/dev/null' or die;
::__observe(__LINE__, 'printf_returns', printf {$null} "%s", "x");

sub who { my $c = caller; $c }
::__observe(__LINE__, 'caller_scalar', who());

sub protoless {}
::__observe(__LINE__, 'prototype_missing', prototype("main::protoless"));

$^A = "";
::__observe(__LINE__, 'formline_returns', formline("@<<\n", "hi"));
