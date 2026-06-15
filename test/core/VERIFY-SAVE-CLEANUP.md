# Atomic Save Temp File Cleanup - Verification Guide

## Overview

This document describes how to verify the atomic save temp file cleanup fixes in `text-io.c`. The fixes address orphaned `.filename.vis.XXXXXX` temp files left behind when atomic save operations fail.

## What Was Fixed

1. **`text_save_begin_atomic`**: Now cleans up temp file and fd on any failure after `mkstemp` succeeds (e.g., `fchmod`, `fchown`, ACL/SELinux preservation failures).

2. **`text_save_commit_atomic`**: Explicitly unlinks temp file on `renameat` failure with errno preservation. Directory `fsync`/`close` failures no longer cause the save to be reported as failed when the `rename` already succeeded (data is safe).

3. **`text_save_commit_inplace`**: Sets `ctx->fd = -1` after close attempt to prevent double-close via `text_save_cancel`.

4. **`text_save_cancel`**: Zeros out `ctx->fd`, `ctx->tmpname.data`, and `ctx->tmpname.length` after cleanup for idempotent behavior.

5. **Error messages in `sam.c`**: Now suggest `:set savemethod inplace` when atomic save fails, and explain symlink/hardlink restrictions.

## Running Tests

### Automated Unit Tests

The tests are in `test/core/text-test.c` and are built and run automatically:

```sh
cd test/core
make          # builds and runs all tests including save cleanup tests
make asan     # run with AddressSanitizer to detect memory issues
make valgrind # run with Valgrind for leak detection
```

### Test Coverage

The following scenarios are verified by the automated tests (test numbers may vary):

| # | Scenario | What is verified |
|---|----------|-----------------|
| 1 | Normal atomic save (new file) | File content correct, no `.vis.*` temp files remain |
| 2 | Normal atomic save (existing file) | Content updated, metadata preserved, no temp files |
| 3 | Atomic save on symlink (fails) | Save correctly rejected, no temp files left behind |
| 4 | Atomic save on hardlink (fails) | Save correctly rejected, no temp files left behind |
| 5 | Atomic save to read-only directory | Save fails, no temp files in target directory |
| 6 | Retry after permission fix | First save fails (read-only dir), fix permissions, retry succeeds, content correct, no temp files |
| 7 | Inplace save via symlink | Inplace fallback works on symlinks, no temp files |
| 8 | All save methods (AUTO/ATOMIC/INPLACE) x all load methods | Full matrix of load+save combinations work correctly |

### Manual Verification

To manually verify temp file cleanup on a problematic filesystem (e.g., sshfs):

```sh
# 1. Mount a remote filesystem
mkdir -p /tmp/sshfs-test
sshfs user@host:/path /tmp/sshfs-test

# 2. Open vis on the mounted filesystem
cd /tmp/sshfs-test
vis testfile.txt

# 3. Edit and save (:w)
# 4. Check for temp files:
ls -la .*.vis.*
# Expected: no matching files

# 5. To force an atomic save failure, create a symlink and try to save:
ln -s testfile.txt link.txt
# In vis: :e link.txt, edit, :w
# Expected: error message suggesting :set savemethod inplace
# Check: no .link.txt.vis.* files left behind

# 6. Retry with inplace method:
# In vis: :set savemethod inplace, then :w
# Expected: save succeeds, no temp files
```

### Failure Modes and Expected Behavior

| Failure scenario | Before fix | After fix |
|---|---|---|
| `fchmod`/`fchown` fails in begin_atomic | Orphaned temp file, fd leak | Temp file unlinked, fd closed, errno preserved |
| `renameat` fails (e.g., sshfs, EXDEV) | Orphaned temp file | Temp file unlinked, errno preserved |
| Dir `fsync` fails after successful rename | Save reported as failed, editor thinks unsaved | Save reported as succeeded (data IS on disk) |
| `close` fails in commit_inplace | Potential double-close via cancel | `fd` set to -1, cancel is safe |
| AUTO fallback: atomic fails, inplace tried | Old atomic temp file leaked if inplace succeeds | Atomic state fully cleaned before inplace attempt |
