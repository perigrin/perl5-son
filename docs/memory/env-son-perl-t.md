# The ratchet needs SON_PERL_T in the cloud container

HOME is /root here, so tools/perl-t-roundtrip.pl looks for perl's t/ at
/root/dev/perl5/t, finds nothing, and the ratchet's "perl t/ does not
regress" subtest fails on "the census found its files (0)". That looks like
a regression but isn't one. Run the ratchet as:

    SON_PERL_T=/home/perigrin/dev/perl5/t SON_CHALK=/home/perigrin/dev/chalk \
      SON_RATCHET=1 prove -l t/roundtrip-ratchet.t

Measured 2026-11-03: perl t/ ROUNDTRIP 11, EMITS_INVALID_PERL 1, the same
before and after producer c7f56e6.
