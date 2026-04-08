# ABOUTME: Tests for B::SoN — the Perl compiler backend that dumps SoN IR graphs.
# ABOUTME: Uses subprocess invocation (perl -MO=SoN) to test the B::* backend interface.

use v5.42.0;
use utf8;
use Test2::V0;
use JSON::PP ();

my $perl = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";

# ====================================================
# Test 1: text output format — header and node content
# ====================================================

subtest 'text output has method header' => sub {
    my $output = `$perl -Ilib -MO=SoN -e 'sub foo { 42 }' 2>&1`;
    like($output, qr/=== main::foo ===/, 'text output has method header for main::foo');
};

subtest 'text output contains Constant node' => sub {
    my $output = `$perl -Ilib -MO=SoN -e 'sub foo { 42 }' 2>&1`;
    like($output, qr/Constant/, 'text output contains Constant node');
};

# ====================================================
# Test 2: JSON output — top-level structure
# ====================================================

subtest 'json output is parseable JSON with correct structure' => sub {
    my $output = `$perl -Ilib -MO=SoN,json -e 'sub foo { 42 }' 2>/dev/null`;
    ok(length($output) > 0, 'json output is non-empty');

    my $data = eval { JSON::PP::decode_json($output) };
    ok(!$@, "JSON parses without error: $@");
    is($data->{version}, 1, 'JSON version is 1');
    ok(exists $data->{methods}{'main::foo'}, 'JSON has main::foo method');
};

# ====================================================
# Test 3: multiple subs all appear in output
# ====================================================

subtest 'multiple subs all appear in json output' => sub {
    my $output = `$perl -Ilib -MO=SoN,json -e 'sub foo { 1 } sub bar { 2 }' 2>/dev/null`;
    my $data = eval { JSON::PP::decode_json($output) };
    ok(!$@, "JSON parses without error: $@");
    ok(exists $data->{methods}{'main::foo'}, 'JSON has main::foo');
    ok(exists $data->{methods}{'main::bar'}, 'JSON has main::bar');
};

# ====================================================
# Test 4: package subs use correct fully-qualified names
# ====================================================

subtest 'package sub appears under correct fully-qualified name' => sub {
    my $output = `$perl -Ilib -MO=SoN,json -e 'package Baz; sub quux { 3 }' 2>/dev/null`;
    my $data = eval { JSON::PP::decode_json($output) };
    ok(!$@, "JSON parses without error: $@");
    ok(exists $data->{methods}{'Baz::quux'}, 'JSON has Baz::quux');
};

# ====================================================
# Test 5: multiple subs in text output each have their own header
# ====================================================

subtest 'text output has separate headers for each sub' => sub {
    my $output = `$perl -Ilib -MO=SoN -e 'sub foo { 1 } sub bar { 2 }' 2>&1`;
    like($output, qr/=== main::foo ===/, 'text output has header for foo');
    like($output, qr/=== main::bar ===/, 'text output has header for bar');
};

# ====================================================
# Test 6: graph structure is valid (nodes, start, returns present)
# ====================================================

subtest 'JSON graph structure has required fields' => sub {
    my $output = `$perl -Ilib -MO=SoN,json -e 'sub foo { 42 }' 2>/dev/null`;
    my $data = eval { JSON::PP::decode_json($output) };
    ok(!$@, "JSON parses without error: $@");

    my $method = $data->{methods}{'main::foo'};
    ok(exists $method->{nodes},   'method has nodes');
    ok(exists $method->{start},   'method has start');
    ok(exists $method->{returns}, 'method has returns');
};

# ====================================================
# Test 7: package filter — single package, JSON
# ====================================================

subtest 'package filter emits only specified package (json)' => sub {
    my $output = `$perl -Ilib -MO=SoN,json,package=Baz -e 'package Baz; sub quux { 3 } package Qux; sub nope { 4 }' 2>/dev/null`;
    my $data = eval { JSON::PP::decode_json($output) };
    ok(!$@, "JSON parses without error: $@");
    ok(exists $data->{methods}{'Baz::quux'}, 'filtered output has Baz::quux');
    ok(!exists $data->{methods}{'Qux::nope'}, 'filtered output excludes Qux::nope');
};

# ====================================================
# Test 8: package filter — multiple packages
# ====================================================

subtest 'multiple package filters emit all specified packages' => sub {
    my $output = `$perl -Ilib -MO=SoN,json,package=Foo,package=Bar -e 'package Foo; sub f { 1 } package Bar; sub b { 2 } package Baz; sub z { 3 }' 2>/dev/null`;
    my $data = eval { JSON::PP::decode_json($output) };
    ok(!$@, "JSON parses without error: $@");
    ok(exists $data->{methods}{'Foo::f'}, 'output has Foo::f');
    ok(exists $data->{methods}{'Bar::b'}, 'output has Bar::b');
    ok(!exists $data->{methods}{'Baz::z'}, 'output excludes Baz::z');
};

# ====================================================
# Test 9: package filter — text format
# ====================================================

subtest 'package filter works with text output' => sub {
    my $output = `$perl -Ilib -MO=SoN,package=Baz -e 'package Baz; sub quux { 3 } package Qux; sub nope { 4 }' 2>&1`;
    like($output, qr/=== Baz::quux ===/, 'text output has Baz::quux header');
    unlike($output, qr/=== Qux::nope ===/, 'text output excludes Qux::nope header');
};

# ====================================================
# Test 10: no package filter — backwards compatible
# ====================================================

subtest 'no package filter emits all packages (backwards compat)' => sub {
    my $output = `$perl -Ilib -MO=SoN,json -e 'package Foo; sub f { 1 } package Bar; sub b { 2 }' 2>/dev/null`;
    my $data = eval { JSON::PP::decode_json($output) };
    ok(!$@, "JSON parses without error: $@");
    ok(exists $data->{methods}{'Foo::f'}, 'unfiltered output has Foo::f');
    ok(exists $data->{methods}{'Bar::b'}, 'unfiltered output has Bar::b');
};

done_testing;
