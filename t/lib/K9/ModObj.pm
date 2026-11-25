# ABOUTME: A followed module for t/a-followed-modules-start-state.t whose file-level code makes an
# ABOUTME: object: no literal says it, and a bless is code beyond plain `our` data (audit 3, N9).
package K9::ModObj;
our $o = bless {}, 'K9::Obj';
1;
