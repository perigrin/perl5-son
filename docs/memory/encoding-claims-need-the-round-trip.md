---
name: encoding-claims-need-the-round-trip
description: "Three wrong encoding claims in one session, same cause: inspecting bytes instead of running the round trip"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-13T21:07:06.663Z
---

I was wrong three times about one encoding finding (2026-09-13), each time by
stating a confident claim without running the case that would settle it.

1. "`->utf8` corrupts the data." I saw `71 ff 80` become `71 c3bf c280` and
   called it corruption. It is the correct UTF-8 encoding of those three
   characters and decoding returns the original. perigrin pushed back.

2. "`->ascii` is the fix." It is correct but escapes every non-ASCII character,
   so ordinary Unicode text grows ~60% and becomes unreadable. Optimising for
   the pathological case.

3. "Those bytes are invalid UTF-8 by definition." Perl's own `utf8::decode`
   ACCEPTS them and recovers the codepoint exactly -- perl implements a
   superset of Unicode. A peer session measured it; I had not.

**Why:** in each case I inspected a representation (hex, byte counts, a
standard's definition) and reasoned from it, instead of running the operation
end to end. "These bytes changed" and "this value changed" are different
findings, and only the second is corruption. A byte string and a character
string are indistinguishable by inspection in perl -- both report
`utf8_flag=off` when built literally, and the flag even groups strings that
behave differently -- so nothing about the representation answers the question.

**How to apply:** for any claim about encoding, serialization or round-tripping,
RUN IT: encode, decode, compare the VALUE, and check whether a failure is loud
or silent. Report what the comparison showed, not what the bytes looked like.
The loud-vs-silent part matters independently: "outside the guarantee" is safe
advice when every failure dies, and dangerous when something substitutes U+FFFD
and carries on.

Corollary worth keeping: a peer re-measuring my finding rather than taking it
on trust is what caught #3, and they were right to, because I had already
handed them #1 as a confident fact and they had written it into a spec.

Related: [[read-generated-output-not-tests]]
