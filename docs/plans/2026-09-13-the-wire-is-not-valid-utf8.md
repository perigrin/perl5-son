# The wire is not valid UTF-8, and `->utf8` is the wrong fix

**Date:** 2026-09-13
**Status:** OPEN. Found while building the deparse oracle; not fixed there
because it is a serializer change, not an emitter one.

## The defect

`SoN::Serialize::JSON` ends with

    return JSON::PP->new->canonical->pretty->encode($data);

with neither `->utf8` nor `->ascii`. `encode` in that mode returns a CHARACTER
string, and printing it to a non-`:utf8` handle writes each character's raw
byte. A string Constant holding a high byte therefore reaches the wire as that
byte, inside JSON every consumer will assume is UTF-8.

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

NOT A PUNCTUATION-VARIABLE PROBLEM. `$^O` being stored as a control character
is a separate thing, fixed in the deparse emitter (25c1411); that byte is
valid UTF-8. These four are STRING CONSTANTS carrying arbitrary bytes, a
different question with a different answer.

## `->utf8` would corrupt the data

The obvious fix is wrong. Measured on the three-character string `q` followed
by bytes 0xff and 0x80, encoded three ways:

    plain (today)   71 ff 80        raw bytes, unreadable as UTF-8
    ->utf8          71 c3bf c280    RE-ENCODED -- a different value
    ->ascii         71 5c75303066 66 5c7530303830    escaped, exact, portable

`->utf8` treats each byte as a character and encodes it, so 0xff becomes the
two bytes c3 bf. For `comp/parser.t`, whose whole point is a malformed UTF-8
string, that silently changes the program under test.

## `->ascii` is the answer

Every non-ASCII byte becomes a `\uXXXX` escape. The output is pure ASCII, so it
is valid UTF-8 (and valid anything else), and decoding returns the original
string unchanged. The cost is a slightly larger wire for the four files that
hold high bytes.

    return JSON::PP->new->canonical->pretty->ascii->encode($data);

## What a fix needs

1. Add `->ascii` at the single encode site in `SoN::Serialize::JSON`.
2. A test asserting the wire decodes as UTF-8 for every corpus file -- the
   property that was never checked. Round-tripping a string Constant holding a
   high byte through encode/decode and comparing bytes is the direct form.
3. Check whether chalk's loader assumes anything about the current encoding.
   It is a Perl consumer, so it is in the same boat the producer is and will
   not have noticed either.

## Why it matters beyond tidiness

The wire is the contract with chalk, and one day with anything else that wants
to read a SoN graph. A JSON document only perl can parse is a JSON document in
name only. The deparse oracle is the first non-perl-side reader this repo has
had, and it found this immediately -- which is itself an argument for having
more than one reader of a format.
