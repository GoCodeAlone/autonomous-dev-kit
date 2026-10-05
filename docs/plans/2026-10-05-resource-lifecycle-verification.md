# Resource lifecycle verification

Task 1: tests written before helper; initial run failed 24/24 because helper was
absent. Implemented CLI/filesystem tests passed 37/37, including real concurrent
writers, protected overlaps, unchanged sentinel bytes, failure/lock timeout,
directory/lock swaps, corrupt metadata and no-follow/nonregular-file rejection.
Repeated first-writer stress passed 30 concurrent batches after reproducing a
native concurrent create/open failure. Duplicate-field and scan-swap attacks
found by independent review have explicit preservation regressions.

Tasks 2/3: all 13 preexisting AGENTS/CI suites plus helper and guidance suites
passed. Python syntax and diff hygiene passed. Guidance contracts are static
evidence, not agent runtime compliance. New path-filtered Ubuntu CI uses Python3
and Bash without new dependencies or runtime pins.

Actual shipped-helper smoke: record → protected report → success closeout →
review candidate; sentinel SHA256 unchanged. Real Go1.27.1 darwin/arm64 builds of
an owned module preserved effective existing GOCACHE; unchanged second build
performed no package compilation or linking. No cold cache, Docker command,
global Go setting change, deletion helper, or host-hook claim.

Installation acceptance remains open; preserve active native plugin paths until
natural completion of consumers or an explicitly authorized maintenance window.
