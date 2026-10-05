#!/usr/bin/env python3
"""Real CLI and filesystem regressions; all resources belong to test fixtures."""
import contextlib
import errno
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HELPER = Path(__file__).resolve().parents[1] / "scripts/job-resources.py"


class Resources(unittest.TestCase):
    def setUp(self):
        self.assertTrue(HELPER.is_file(), "resource helper must exist")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name).resolve() / "project"
        self.project.mkdir()
        self.resource = self.project / ".autodev/tmp/job"
        self.resource.mkdir(parents=True)
        self.sentinel = self.resource / "sentinel"
        self.sentinel.write_bytes(b"unique data\x00keep")
        self.state = self.project / ".autodev/state/job-resources.json"

    def args(self, *args):
        return ["--project", str(self.project), *map(str, args)]

    def cli(self, *args, error=False):
        result = subprocess.run([sys.executable, str(HELPER), *self.args(*args)],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 2 if error else 0, result.stderr)
        output = json.loads(result.stderr if error else result.stdout)
        self.assertIn("error" if error else "resources", output)
        self.assertEqual(self.sentinel.read_bytes(), b"unique data\x00keep")
        return output

    def record(self, session="s", job="j", path=None, **options):
        args = ["record", "--session", session, "--job", job,
                "--kind", options.pop("kind", "directory"),
                "--resource", str(path or self.resource)]
        for key, value in options.items():
            args += ["--" + key, value]
        return self.cli(*args)

    def disposable(self, **kwargs):
        return self.record(purpose="test-fixture", retention="disposable",
                           reason="isolated cold-cache test", **kwargs)

    def close(self, session="s", job="j", outcome="success", error=False):
        return self.cli("closeout", "--session", session, "--job", job,
                        "--outcome", outcome, error=error)

    def candidates(self, output=None):
        return [r for r in (output or self.cli("report"))["resources"]
                if r["status"] == "review-candidate"]

    def module(self):
        spec = importlib.util.spec_from_file_location("job_resources", HELPER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def in_process(self, module, *args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = module.main(self.args(*args))
        self.assertEqual(code, 2, stdout.getvalue())
        self.assertIn("error", json.loads(stderr.getvalue()))

    def test_empty_report_does_not_create_metadata(self):
        self.cli("report")
        self.assertFalse((self.project / ".autodev/state").exists())

    def test_active_and_unknown_are_protected(self):
        self.record()
        self.assertFalse(self.candidates())
        self.close()
        self.assertFalse(self.candidates())

    def test_positive_candidate_in_normal_git_project(self):
        (self.project / ".git").mkdir()
        self.disposable()
        self.assertFalse(self.candidates())
        output = self.close()
        self.assertEqual(len(self.candidates(output)), 1)
        self.close()  # identical closeout is idempotent

    def test_failed_closeout_stays_protected(self):
        self.disposable()
        self.close(outcome="failure")
        self.assertFalse(self.candidates())
        before = self.state.read_bytes()
        self.close(error=True)
        self.assertEqual(self.state.read_bytes(), before)

    def test_cross_session_and_closed_job_rejected(self):
        self.disposable()
        self.close(session="other", error=True)
        self.close()
        before = self.state.read_bytes()
        self.cli("record", "--session", "s", "--job", "j", "--kind", "directory",
                 "--resource", self.resource, error=True)
        self.assertEqual(self.state.read_bytes(), before)

    def test_shared_resource_requires_every_owner_closeout(self):
        self.disposable()
        self.disposable(session="other")
        self.close()
        self.assertFalse(self.candidates())
        self.close(session="other")
        self.assertEqual(len(self.candidates()), 1)

    def test_retention_and_purpose_cannot_be_downgraded(self):
        self.record(purpose="database")
        self.disposable(session="other")
        self.close()
        self.close(session="other")
        self.assertFalse(self.candidates())

    def test_external_reusable_cache_unchanged(self):
        external = Path(self.temp.name) / "stable-cache"
        external.mkdir()
        sentinel = external / "data"
        sentinel.write_bytes(b"warm-cache")
        self.record(path=external, purpose="build-cache", retention="reusable")
        self.close()
        self.assertFalse(self.candidates())
        self.assertEqual(sentinel.read_bytes(), b"warm-cache")

    def test_invalid_disposable_declarations(self):
        for kind, path, purpose in [("docker-volume", "db-volume", "test-fixture"),
                                    ("worktree", self.resource, "test-fixture"),
                                    ("directory", Path(self.temp.name), "test-fixture"),
                                    ("directory", self.resource, "database")]:
            with self.subTest(kind=kind, path=path, purpose=purpose):
                self.cli("record", "--session", "s", "--job", kind,
                         "--kind", kind, "--resource", path, "--purpose", purpose,
                         "--retention", "disposable", "--reason", "test", error=True)

    def test_docker_and_worktree_remain_protected(self):
        self.record(kind="docker-volume", path="test-volume")
        self.record(job="w", kind="worktree")
        self.close()
        self.close(job="w")
        self.assertFalse(self.candidates())

    def test_reason_required_and_missing_directory_protected(self):
        self.cli("record", "--session", "s", "--job", "j", "--kind", "directory",
                 "--resource", self.resource, "--purpose", "test-fixture",
                 "--retention", "disposable", error=True)
        self.disposable()
        self.close()
        self.sentinel.unlink()
        self.resource.rmdir()
        self.sentinel = self.project / "preserved"
        self.sentinel.write_bytes(b"unique data\x00keep")
        self.assertFalse(self.candidates())

    def test_symlink_and_traversal_rejected(self):
        link = self.project / ".autodev/tmp/link"
        link.symlink_to(Path(self.temp.name), target_is_directory=True)
        for path in [link, self.resource / "../../../outside"]:
            self.cli("record", "--session", "s", "--job", "j", "--kind", "directory",
                     "--resource", path, "--purpose", "test-fixture",
                     "--retention", "disposable", "--reason", "test", error=True)

    def test_report_revalidates_symlink_descendant(self):
        self.disposable()
        self.close()
        (self.resource / "escape").symlink_to(Path(self.temp.name))
        self.assertFalse(self.candidates())

    def test_nested_and_ancestor_worktrees(self):
        self.disposable()
        self.close()
        nested = self.resource / "nested"
        nested.mkdir()
        (nested / ".git").write_text("gitdir: unrelated\n")
        self.assertFalse(self.candidates())
        (nested / ".git").unlink()
        (self.resource.parent / ".git").mkdir()
        self.assertFalse(self.candidates())

    def test_protected_overlap_both_directions(self):
        self.disposable()
        child = self.resource / "cache"
        child.mkdir()
        self.record(session="other", path=child, purpose="build-cache", retention="reusable")
        self.close()
        self.close(session="other")
        self.assertFalse(self.candidates())
        self.record(session="parent", path=self.resource.parent, purpose="database")
        self.close(session="parent")
        self.assertFalse(self.candidates())

    def test_unknown_owner_is_protected(self):
        self.disposable()
        self.close()
        data = json.loads(self.state.read_text())
        next(iter(data["resources"].values()))["owners"].append("missing-owner")
        self.state.write_text(json.dumps(data))
        self.assertFalse(self.candidates())

    def test_protected_parent_suppresses_disposable_child(self):
        self.record(session="parent", path=self.resource.parent, purpose="database")
        self.disposable()
        self.close()
        self.close(session="parent")
        self.assertFalse(self.candidates())

    def test_fifo_metadata_rejected_without_hanging(self):
        self.record()
        self.state.unlink()
        os.mkfifo(self.state)
        self.cli("report", error=True)

    def test_changed_protected_path_preserves_candidates(self):
        self.disposable()
        self.close()
        protected = self.project / "cache"
        protected.mkdir()
        self.record(session="cache", path=protected, purpose="build-cache", retention="reusable")
        protected.rmdir()
        protected.symlink_to(self.resource, target_is_directory=True)
        self.assertFalse(self.candidates())

    def test_corrupt_future_and_wrong_project_preserved(self):
        self.record()
        original = json.loads(self.state.read_text())
        future = dict(original, schema=999)
        wrong = dict(original, project="/unknown")
        duplicate = json.dumps(original).replace('"schema": 1', '"schema": 999, "schema": 1')
        for text in ["{broken", json.dumps(future), json.dumps(wrong), "[]", duplicate]:
            self.state.write_text(text)
            self.cli("report", error=True)
            self.assertEqual(self.state.read_text(), text)

    def test_duplicate_fields_preserved_for_all_commands(self):
        self.record()
        duplicate = self.state.read_text().replace('"owners": [', '"owners": ["unknown"], "owners": [')
        for args in [("report",), ("record", "--session", "other", "--job", "j", "--kind", "directory",
                                  "--resource", str(self.resource)),
                     ("closeout", "--session", "s", "--job", "j", "--outcome", "success")]:
            self.state.write_text(duplicate)
            self.cli(*args, error=True)
            self.assertEqual(self.state.read_text(), duplicate)

    def test_missing_existing_lock_is_not_recreated(self):
        self.record()
        before = self.state.read_bytes()
        self.state.with_suffix(".lock").unlink()
        self.cli("record", "--session", "other", "--job", "j", "--kind", "directory",
                 "--resource", self.resource, error=True)
        self.assertFalse(self.state.with_suffix(".lock").exists())
        self.assertEqual(self.state.read_bytes(), before)

    def test_candidate_scan_swaps_and_changes_are_protected(self):
        for mode in ["candidate", "ancestor", "descendant", "new-entry"]:
            with self.subTest(mode=mode):
                # Each subcase uses its own declared resource, avoiding restored paths.
                resource = self.resource / mode
                resource.mkdir()
                sentinel = resource / "unique"
                sentinel.write_bytes(b"original")
                nested = resource / "nested"
                nested.mkdir()
                self.disposable(job=mode, path=resource)
                self.close(job=mode)
                module = self.module()
                original = module.os.scandir
                target = nested if mode == "descendant" else resource
                target_inode = target.stat().st_ino
                triggered = [False]

                def barrier(fd):
                    if not triggered[0] and os.fstat(fd).st_ino == target_inode:
                        triggered[0] = True
                        if mode == "new-entry":
                            (resource / ".git").mkdir()
                        else:
                            moved = target if mode != "ancestor" else resource.parent
                            saved = moved.with_name(moved.name + "-saved")
                            moved.rename(saved)
                            moved.mkdir()
                            (moved / ".git").mkdir()
                    return original(fd)

                stdout = io.StringIO()
                with mock.patch.object(module.os, "scandir", barrier), contextlib.redirect_stdout(stdout):
                    self.assertEqual(module.main(self.args("report")), 0)
                self.assertTrue(triggered[0])
                row = next(r for r in json.loads(stdout.getvalue())["resources"] if r["resource"] == str(resource))
                self.assertEqual(row["status"], "protected")
                if mode == "ancestor":
                    self.assertEqual((resource.parent.with_name(resource.parent.name + "-saved") /
                                      mode / "unique").read_bytes(), b"original")
                    (resource.parent / ".git").rmdir()
                    resource.parent.rmdir()
                    resource.parent.with_name(resource.parent.name + "-saved").rename(resource.parent)
                elif mode == "candidate":
                    self.assertEqual((resource.with_name(resource.name + "-saved") / "unique").read_bytes(), b"original")
                else:
                    self.assertEqual(sentinel.read_bytes(), b"original")

    def test_metadata_symlinks_rejected_without_external_writes(self):
        self.record()
        external = Path(self.temp.name) / "external"
        external.mkdir()
        for name in ["job-resources.json", "job-resources.lock"]:
            target = self.state.parent / name
            backup = target.with_suffix(".saved")
            target.rename(backup)
            target.symlink_to(external / "unknown")
            self.cli("report", error=True)
            self.assertEqual(list(external.iterdir()), [])
            target.unlink()
            backup.rename(target)

    def test_project_swap_during_scan_is_protected(self):
        self.disposable()
        self.close()
        module = self.module()
        original = module.os.scandir
        inode = self.resource.stat().st_ino
        triggered = [False]
        saved = self.project.with_name("original-project")

        def barrier(fd):
            if not triggered[0] and os.fstat(fd).st_ino == inode:
                triggered[0] = True
                self.project.rename(saved)
                self.resource.mkdir(parents=True)
                (self.resource / ".git").mkdir()
                (self.resource / "replacement-data").write_bytes(b"protected replacement")
            return original(fd)

        stdout = io.StringIO()
        with mock.patch.object(module.os, "scandir", barrier), contextlib.redirect_stdout(stdout):
            self.assertEqual(module.main(self.args("report")), 0)
        self.assertTrue(triggered[0])
        self.assertFalse(self.candidates(json.loads(stdout.getvalue())))
        self.assertEqual((saved / ".autodev/tmp/job/sentinel").read_bytes(), b"unique data\x00keep")
        self.assertEqual((self.resource / "replacement-data").read_bytes(), b"protected replacement")

    def test_new_entry_after_enumeration_is_protected(self):
        self.disposable()
        self.close()
        module = self.module()
        original = module.os.scandir
        inode = self.resource.stat().st_ino

        @contextlib.contextmanager
        def barrier(fd):
            with original(fd) as entries:
                yield entries
            if os.fstat(fd).st_ino == inode:
                (self.resource / ".git").mkdir()

        stdout = io.StringIO()
        with mock.patch.object(module.os, "scandir", barrier), contextlib.redirect_stdout(stdout):
            self.assertEqual(module.main(self.args("report")), 0)
        self.assertFalse(self.candidates(json.loads(stdout.getvalue())))
        self.assertEqual(self.sentinel.read_bytes(), b"unique data\x00keep")

    def test_metadata_directory_symlink_rejected(self):
        self.record()
        directory = self.state.parent
        directory.rename(directory.with_name("saved"))
        external = Path(self.temp.name) / "outside"
        external.mkdir()
        directory.symlink_to(external, target_is_directory=True)
        self.cli("report", error=True)
        self.assertEqual(list(external.iterdir()), [])

    def test_failed_atomic_write_preserves_ledger(self):
        self.record()
        before = self.state.read_bytes()
        module = self.module()
        with mock.patch.object(module.os, "replace", side_effect=OSError(errno.ENOSPC, "full")):
            self.in_process(module, "closeout", "--session", "s", "--job", "j", "--outcome", "success")
        self.assertEqual(self.state.read_bytes(), before)
        self.assertEqual(sorted(p.name for p in self.state.parent.iterdir()),
                         ["job-resources.json", "job-resources.lock"])

    def test_lock_failure_preserves_ledger(self):
        self.record()
        before = self.state.read_bytes()
        module = self.module()
        with mock.patch.object(module.fcntl, "flock", side_effect=OSError(errno.EIO, "lock")):
            self.in_process(module, "closeout", "--session", "s", "--job", "j", "--outcome", "success")
        self.assertEqual(self.state.read_bytes(), before)

    def test_lock_timeout_and_unsupported_platform_preserve_state(self):
        self.record()
        before = self.state.read_bytes()
        module = self.module()
        with mock.patch.object(module, "LOCK_TIMEOUT", 0), mock.patch.object(
                module.fcntl, "flock", side_effect=BlockingIOError(errno.EAGAIN, "busy")):
            self.in_process(module, "closeout", "--session", "s", "--job", "j", "--outcome", "success")
        with mock.patch.object(module, "fcntl", None):
            self.in_process(module, "closeout", "--session", "s", "--job", "j", "--outcome", "success")
        self.assertEqual(self.state.read_bytes(), before)

    def test_unreadable_tree_is_protected(self):
        self.disposable()
        self.close()
        module = self.module()
        with mock.patch.object(module.os, "scandir", side_effect=PermissionError("unreadable")):
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(module.main(self.args("report")), 0)
            self.assertFalse(self.candidates(json.loads(stdout.getvalue())))

    def test_real_project_path_alias_is_supported(self):
        alias = Path(self.temp.name) / "project-alias"
        alias.symlink_to(self.project, target_is_directory=True)
        result = subprocess.run([sys.executable, str(HELPER), "--project", str(alias),
            "record", "--session", "s", "--job", "j", "--kind", "directory",
            "--resource", str(alias / ".autodev/tmp/job"), "--purpose", "test-fixture",
            "--retention", "disposable", "--reason", "test"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.candidates(self.close())), 1)

    def test_directory_and_lock_swap_detected_before_write(self):
        for swap in ["directory", "lock"]:
            with self.subTest(swap=swap):
                self.record(session=swap)
                before = self.state.read_bytes()
                module = self.module()
                original = module.Ledger.validate
                calls = [0]
                external = Path(self.temp.name) / ("outside-" + swap)
                external.mkdir()

                def barrier(ledger):
                    calls[0] += 1
                    if calls[0] == 3:
                        if swap == "directory":
                            self.state.parent.rename(self.state.parent.with_name("saved"))
                            self.state.parent.symlink_to(external, target_is_directory=True)
                        else:
                            lock = self.state.with_suffix(".lock")
                            lock.rename(lock.with_suffix(".saved"))
                            lock.touch()
                    return original(ledger)

                with mock.patch.object(module.Ledger, "validate", barrier):
                    self.in_process(module, "closeout", "--session", swap, "--job", "j", "--outcome", "success")
                self.assertEqual(list(external.iterdir()), [])
                if swap == "directory":
                    self.state.parent.unlink()
                    self.state.parent.with_name("saved").rename(self.state.parent)
                else:
                    self.state.with_suffix(".lock").unlink()
                    self.state.with_suffix(".saved").rename(self.state.with_suffix(".lock"))
                self.assertEqual(self.state.read_bytes(), before)

    def test_budget_exhaustion_is_protected(self):
        self.disposable()
        self.close()
        module = self.module()
        with mock.patch.object(module, "MAX_ENTRIES", 0):
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(module.main(self.args("report")), 0)
            self.assertFalse(self.candidates(json.loads(stdout.getvalue())))

    def test_parallel_writers_preserve_owners_and_stable_lock(self):
        self.disposable()
        inode = self.state.with_suffix(".lock").stat().st_ino
        processes = []
        for i in range(8):
            processes.append(subprocess.Popen([sys.executable, str(HELPER), *self.args(
                "record", "--session", "parallel-" + str(i), "--job", "job",
                "--kind", "directory", "--resource", self.resource,
                "--purpose", "test-fixture", "--retention", "disposable", "--reason", "test")],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
        completed = [(process.communicate(timeout=15), process.returncode) for process in processes]
        for (stdout, stderr), code in completed:
            self.assertEqual(code, 0, stderr)
            self.assertIn("resources", json.loads(stdout))
        data = json.loads(self.state.read_text())
        self.assertEqual(len(data["jobs"]), 9)
        self.assertEqual(len(next(iter(data["resources"].values()))["owners"]), 9)
        self.assertEqual(self.state.with_suffix(".lock").stat().st_ino, inode)
        self.assertFalse(self.candidates())

    def test_parallel_distinct_resources_preserved(self):
        processes = []
        for i in range(4):
            path = self.resource / str(i)
            path.mkdir()
            processes.append(subprocess.Popen([sys.executable, str(HELPER), *self.args(
                "record", "--session", str(i), "--job", "job", "--kind", "directory",
                "--resource", path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
        completed = [(process.communicate(timeout=15), process.returncode) for process in processes]
        for (_, stderr), code in completed:
            self.assertEqual(code, 0, stderr)
        data = json.loads(self.state.read_text())
        self.assertEqual(len(data["jobs"]), 4)
        self.assertEqual(len(data["resources"]), 4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
