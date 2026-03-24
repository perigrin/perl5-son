# ABOUTME: Basic load test for the SoN distribution.
# ABOUTME: Verifies that the top-level module compiles and loads.

use v5.42.0;
use Test2::V0;

ok(lives { require SoN }, 'SoN loads') or diag($@);

done_testing;
