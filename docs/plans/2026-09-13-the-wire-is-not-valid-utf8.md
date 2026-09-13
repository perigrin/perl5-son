# The wire is not valid UTF-8, and `->utf8` is the fix

**Date:** 2026-09-13
**Status:** OPEN. Found while building the deparse oracle; not fixed there
because it is a serializer change, not an emitter one.

**Corrected 2026-09-13:** an earlier revision of this document said `->utf8`
would corrupt the data and `->ascii` was the answer. That was wrong. See
"What the first measurement got wrong" below.

## The defect

`SoN::Serialize::JSON` ends with

    return JSON::PP->new->canonical->pretty->encode($data);

with neither `->utf8` nor `->ascii`. `encode` in that mode returns a CHARACTER
string, and printing it to a non-`:utf8` handle writes each character's
low byte. A string Constant holding a character above U+007F therefore reaches
the wire as a raw byte, inside JSON every consumer will assume is UTF-8.

Measured across base+comp -- **4 of 34 files** emit a wire that is not valid
UTF-8:

    base/lex.t         byte 0xdf    in a string Constant
    base/num.t         byte 0xf0    from pack("d", 1)
    comp/parser.t      byte 0xff    a deliberately malformed UTF-8 test string
    comp/parser_run.t  byte 0xb6    in a string Constant

Perl's own JSON decoder accepts this happily, which is why it has gone
unnoticed: the producer writes the wire and the producer's tests read it back.
It breaks the moment anything else reads it. Python's `json.load` refuses:

    UnicodeDecodeError: utf-8 codec can't decode byte 0xf0 in position 149111

That is how it was found -- a corpus script could not decode a file the perl
side had no trouble with.

## `->utf8` is the fix

The values arriving at the serializer are CHARACTER strings, not byte strings.
Measured on the live wire for `use utf8; my $u = "café"; my $b = "q\xff\x80"`:

    value bytes=636166e9   utf8_flag=ON     "café"  -- 4 chars, U+00E9 last
    value bytes=71ff80     utf8_flag=ON     3 chars, U+00FF and U+0080

Perl has already decoded them. So `->utf8` does not re-encode anything twice;
it encodes characters to bytes exactly once, which is what a byte-oriented
wire needs.

All three modes ROUND-TRIP the value correctly. Only one of them produces a
wire that is valid UTF-8 AND readable:

    mode     round-trips   wire is UTF-8   "café ☺ naïve"
    plain    yes           NO              café ☺ naïve          (24 bytes)
    ascii    yes           yes             café ☺ ...  (39 bytes)
    utf8     yes           yes             café ☺ naïve          (28 bytes)

`->ascii` is correct but optimises for the pathological case at the cost of
every ordinary one: any perl program containing non-ASCII text -- an accented
identifier in a string, a UTF-8 comment that reaches a Constant -- becomes
escape soup, and the wire grows ~60%. Four files in the corpus have raw high
bytes; considerably more will one day have ordinary Unicode.

    return JSON::PP->new->canonical->pretty->utf8->encode($data);

## What the first measurement got wrong

The earlier revision measured `"q\xff\x80"` in a one-line perl script and
reported that `->utf8` turned `71 ff 80` into `71 c3bf c280` -- reading that as
corruption, and concluding `->ascii` was the only exact option.

The bytes were right and the interpretation was wrong. That IS the correct
UTF-8 encoding of the three characters U+0071, U+00FF, U+0080, and decoding it
returns the original string. It only looks like corruption if you believe the
value is a BYTE string that should pass through untouched.

Perl cannot tell the two apart by inspection -- measured, a byte string
`"q\xff\x80"` and a character string `"caf\x{e9}"` both report `utf8_flag=off`
when built literally in a script, so the flag proves nothing about intent. What
settles it is looking at the values the producer actually hands the serializer,
which carry `utf8_flag=ON`. They are characters.

The lesson worth keeping: "these bytes changed" is not the same finding as
"this value changed", and only the second one matters. Check the round trip,
not the hex.

## What a fix needs

1. Add `->utf8` at the single encode site in `SoN::Serialize::JSON`.
2. A test asserting the wire decodes as UTF-8 for every corpus file -- the
   property that was never checked. Round-tripping a Constant holding a
   character above U+007F through encode/decode and comparing is the direct
   form.
3. Check whether chalk's loader decodes the wire as UTF-8 or reads it raw. It
   is a Perl consumer, so it has been getting away with the same thing the
   producer has.

## Why it matters beyond tidiness

The wire is the contract with chalk, and one day with anything else that wants
to read a SoN graph. A JSON document only perl can parse is a JSON document in
name only. The deparse oracle is the first non-perl-side reader this repo has
had, and it found this immediately -- which is itself an argument for having
more than one reader of a format.
