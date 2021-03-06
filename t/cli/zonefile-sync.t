#!/usr/bin/env perl

use strict;
use warnings;

use Zonemod::Test::Cli qw(run $OUT_DIR);

use Test::More;
use Test::Deep qw(cmp_set);
use Test::File::Contents;

my ($out, $exit);

# ------------------------------------------------------
# - TEST: bad invocations                              -
# ------------------------------------------------------

($out, $exit) = run('sync');
isnt($exit, 0, "Exit with bad status code when usage invalid (no args)");
like($out, qr/positional arguments/i, "Error message contains reference to 'positional arguments'");
like($out, qr/source/i,               "Error message contains reference to 'source'");
like($out, qr/target/i,               "Error message contains reference to 'target'");

($out, $exit) = run('sync ./test');
isnt($exit, 0, "Exit with bad status code when usage invalid (single arg)");
like($out, qr/positional arguments/i, "Error message contains reference to 'positional arguments'");
like($out, qr/target/i,               "Error message contains reference to 'target'");

($out, $exit) = run('sync bad-protocol://test ./out.zone');
isnt($exit, 0, "Exit with bad status code when usage invalid (unparseable arg)");
like($out, qr/no.+provider/i, "Error message contains reference to bad 'provider'");
like($out, qr/bad-protocol/i, "Error message contains reference to the bad argument");
like($out, qr/source/i,       "Error message specifies which argument was invalid");

($out, $exit) = run('sync ./t/data/in-dir bad-protocol://test');
isnt($exit, 0, "Exit with bad status code when usage invalid (unparseable arg)");
like($out, qr/no.+provider/i, "Error message contains reference to bad 'provider'");
like($out, qr/bad-protocol/i, "Error message contains reference to the bad argument");
like($out, qr/target/i,       "Error message specifies which argument was invalid");

($out, $exit) = run('sync ./t/data/in-dir ./out.zone --hello');
isnt($exit, 0, "Exit with bad status code when invalid cli switch is specified");
like($out, qr/unknown option/i, "Error message contains reference to 'unknown option'");
like($out, qr/hello/i,          "Error message contains the invalid switch name");

# ------------------------------------------------------
# - TEST: --delete and --managed behavior              -
# ------------------------------------------------------

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone');
is($exit, 0, "Sync dir to new file works");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
}, "Sync to new file works as expected");

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone', {
	'out.zone' => q{
; this comment will get nuked... as will the next record...
test-a	100	IN	A	127.0.0.5
test-e	100	IN	TXT	"testing"
}});
is($exit, 0, "Sync dir to existing file");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
test-e	100	IN	TXT	"testing"
}, "Sync to existing file merges records with existing items");

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --dryrun', {
	'out.zone' => q{
; this comment will get nuked... as will the next record...
test-a	100	IN	A	127.0.0.5
test-e	100	IN	TXT	"testing"
}});
is($exit, 0, "Sync dir to existing file");
file_contents_eq('./t/data/output/out.zone', q{
; this comment will get nuked... as will the next record...
test-a	100	IN	A	127.0.0.5
test-e	100	IN	TXT	"testing"
}, "Sync with dryrun flag will make no changes");

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete', {
	'out.zone' => q{
; this comment will get nuked... as will the next record...
test-a	100	IN	A	127.0.0.5
test-e	100	IN	TXT	"testing"
}});
is($exit, 0, "Sync dir to existing file (with delete)");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
}, "Sync --delete will clear existing items not in source");

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone', {
	'out.zone' => q{
; this comment will get nuked... as will the next record...
test-a	100	IN	A	127.0.0.5
test-e	100	IN	TXT	"testing"
test-f	100	IN	TXT	"testing"
},
	'managed.zone' => q{
test-a	100	IN	A   127.0.0.1
test-e	100	IN	TXT	"testing"
}});
is($exit, 0, "Sync dir to existing file (with delete and managed)");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
test-f	100	IN	TXT	"testing"
}, "Sync --delete will NOT clear items that are not in --managed set");

# ------------------------------------------------------
# - TEST: Prevent overwrite behaviour with managed     -
# ------------------------------------------------------
($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone', {
	'out.zone'     => q{test-a 999 IN A	255.255.255.255},
	'managed.zone' => q{test-b 600 IN	CNAME	example.com},
});
isnt($exit, 0, "Sync will avoid overwriting existing record if its not in managed set (default grouping)");
file_contents_eq('./t/data/output/out.zone', q{test-a 999 IN A	255.255.255.255});
file_contents_eq('./t/data/output/managed.zone', q{test-b 600 IN	CNAME	example.com});

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone --grouping host', {
	'out.zone'     => q{test-a 999 IN A	255.255.255.255},
	'managed.zone' => q{test-b 600 IN	CNAME	example.com},
});
isnt($exit, 0, "Sync will avoid overwriting existing record if its not in managed set (group=host)");
file_contents_eq('./t/data/output/out.zone', q{test-a 999 IN A	255.255.255.255});
file_contents_eq('./t/data/output/managed.zone', q{test-b 600 IN	CNAME	example.com});

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone --grouping type', {
	'out.zone'     => q{test-a 999 IN A	255.255.255.255},
	'managed.zone' => q{test-b 600 IN	CNAME	example.com},
});
isnt($exit, 0, "Sync will avoid overwriting existing record if its not in managed set (group=type)");
file_contents_eq('./t/data/output/out.zone', q{test-a 999 IN A	255.255.255.255});
file_contents_eq('./t/data/output/managed.zone', q{test-b 600 IN	CNAME	example.com});

# We can create records in grouping none mode, as there is no overlap
($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone --grouping none', {
	'out.zone'     => q{test-a 999 IN A	255.255.255.255},
	'managed.zone' => q{test-b 600 IN	CNAME	example.com},
});
is($exit, 0, "Sync will avoid overwriting existing record if its not in managed set");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	999	IN	A	255.255.255.255
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
});

# Conflicting record on host, but NOT type
($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone --grouping host', {
	'out.zone'     => q{test-a 999 IN TXT	"conflict"},
	'managed.zone' => q{test-b 600 IN	CNAME	example.com},
});
isnt($exit, 0, "Sync will avoid overwriting existing record if its not in managed set (group=host)");
file_contents_eq('./t/data/output/out.zone', q{test-a 999 IN TXT	"conflict"});
file_contents_eq('./t/data/output/managed.zone', q{test-b 600 IN	CNAME	example.com});

# We can create records in grouping type mode, as there is no overlap
($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone --grouping type', {
	'out.zone'     => q{test-a 999 IN TXT	"conflict"},
	'managed.zone' => q{test-b 600 IN	CNAME	example.com},
});
is($exit, 0, "Sync will avoid overwriting existing record if its not in managed set (group=type)");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-a	999	IN	TXT	"conflict"
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
});

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone --grouping none', {
	'out.zone'     => q{test-a 999 IN TXT	"conflict"},
	'managed.zone' => q{test-b 600 IN	CNAME	example.com},
});
is($exit, 0, "Sync will avoid overwriting existing record if its not in managed set (group=none)");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-a	999	IN	TXT	"conflict"
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
});

# ------------------------------------------------------
# - TEST: sync to dir                                  -
# ------------------------------------------------------
($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out/');
is($exit, 0, "Sync to non-existant dir will create it");
file_contents_eq('./t/data/output/out/test-a.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
}, 'Created test-a.zone');
file_contents_eq('./t/data/output/out/test-b.zone', q{test-b	600	IN	CNAME	example.com
});
file_contents_eq('./t/data/output/out/test-c.zone', q{test-c	600	IN	TXT	"Test Text"
});

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out/');
is($exit, 0, "Sync to non-existant dir will create it");
file_contents_eq('./t/data/output/out/test-a.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
});
file_contents_eq('./t/data/output/out/test-b.zone', q{test-b	600	IN	CNAME	example.com
});
file_contents_eq('./t/data/output/out/test-c.zone', q{test-c	600	IN	TXT	"Test Text"
});

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out', { out => [] });
is($exit, 0, "Syncing to dir without trailing slash will act as dir sync rather than file sync");
file_contents_eq('./t/data/output/out/test-a.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
});
file_contents_eq('./t/data/output/out/test-b.zone', q{test-b	600	IN	CNAME	example.com
});
file_contents_eq('./t/data/output/out/test-c.zone', q{test-c	600	IN	TXT	"Test Text"
});

($out, $exit) = run('sync ./t/data/input/dir ./t/data/output/out/', {
	'out/test.txt' => 'hello world',
	'out/test-a.zone' => q{test-a	100	IN	TXT	"existing"
},
	'out/test-z.zone' => q{test-z	100	IN	A	127.0.0.255
},
});
is($exit, 0, "Existing non-zone files are ignored, existing zone files are merged");
file_contents_eq('./t/data/output/out/test-a.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-a	100	IN	TXT	"existing"
});
file_contents_eq('./t/data/output/out/test-b.zone', q{test-b	600	IN	CNAME	example.com
});
file_contents_eq('./t/data/output/out/test-c.zone', q{test-c	600	IN	TXT	"Test Text"
});
file_contents_eq('./t/data/output/out/test-z.zone', q{test-z	100	IN	A	127.0.0.255
});
file_contents_eq('./t/data/output/out/test.txt', q{hello world});


done_testing();
