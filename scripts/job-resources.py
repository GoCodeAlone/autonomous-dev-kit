#!/usr/bin/env python3
"""Optional resource attribution ledger. Writes metadata; never deletes resources."""
import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import time

try:
    import fcntl
except ImportError:
    fcntl = None

MAX_ENTRIES = 10000
LOCK_TIMEOUT = 5
MAX_METADATA = 1024 * 1024
KINDS = ("directory", "docker-volume", "worktree")
PURPOSES = ("build-cache", "test-fixture", "database", "unknown")
RETENTIONS = ("disposable", "reusable", "protected")
NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
DIRECTORY = getattr(os, "O_DIRECTORY", 0)


class Invalid(ValueError):
    pass


def identity(info):
    return info.st_dev, info.st_ino


def key(*parts):
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()


def text(value, limit=200):
    return isinstance(value, str) and 0 < len(value) <= limit and not any(
        ord(c) < 32 or ord(c) == 127 for c in value)


def beneath(path, parent):
    return path != parent and parent in path.parents


def regular(fd):
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise Invalid("metadata must be a regular, unshared file")


class Ledger:
    """Stable flock inode and descriptor-relative metadata transactions."""
    def __init__(self, project, write):
        self.project, self.write = project, write
        self.fds, self.links, self.lock = [], [], None
        self.empty = False

    def __enter__(self):
        if fcntl is None or not NOFOLLOW or not DIRECTORY:
            raise Invalid("POSIX flock/no-follow directories required; use manual guidance")
        try:
            fd = os.open(self.project, os.O_RDONLY | DIRECTORY | NOFOLLOW)
            self.fds.append(fd)
            for name in (".autodev", "state"):
                parent = fd
                try:
                    fd = os.open(name, os.O_RDONLY | DIRECTORY | NOFOLLOW, dir_fd=parent)
                except FileNotFoundError:
                    if not self.write:
                        self.empty = True
                        return self
                    try:
                        os.mkdir(name, 0o700, dir_fd=parent)
                    except FileExistsError:
                        pass  # another cooperating first writer created it
                    fd = os.open(name, os.O_RDONLY | DIRECTORY | NOFOLLOW, dir_fd=parent)
                self.fds.append(fd)
                self.links.append((parent, name, fd))
            self.directory = fd
            if not self.write:
                try:
                    os.stat("job-resources.json", dir_fd=fd, follow_symlinks=False)
                except FileNotFoundError:
                    self.empty = True
                    return self
            flags = os.O_RDWR | NOFOLLOW | (os.O_CREAT if self.write else 0)
            self.lock = os.open("job-resources.lock", flags, 0o600, dir_fd=fd)
            regular(self.lock)
            deadline = time.monotonic() + LOCK_TIMEOUT
            while True:
                try:
                    fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        raise Invalid("metadata lock timeout; ownership unchanged")
                    time.sleep(0.05)
            self.validate()
            return self
        except Exception:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_):
        if self.lock is not None:
            os.close(self.lock)  # closing releases flock even after failed acquisition
            self.lock = None
        for fd in reversed(self.fds):
            os.close(fd)
        self.fds = []

    def validate(self):
        if identity(os.stat(self.project, follow_symlinks=False)) != identity(os.fstat(self.fds[0])):
            raise Invalid("project directory changed")
        for parent, name, fd in self.links:
            info = os.stat(name, dir_fd=parent, follow_symlinks=False)
            if not stat.S_ISDIR(info.st_mode) or identity(info) != identity(os.fstat(fd)):
                raise Invalid("metadata directory changed")
        info = os.stat("job-resources.lock", dir_fd=self.directory, follow_symlinks=False)
        if identity(info) != identity(os.fstat(self.lock)) or not stat.S_ISREG(info.st_mode):
            raise Invalid("metadata lock changed")

    def load(self):
        empty = {"schema": 1, "project": str(self.project), "jobs": {}, "resources": {}}
        if self.empty:
            return empty
        self.validate()
        try:
            fd = os.open("job-resources.json", os.O_RDONLY | os.O_NONBLOCK | NOFOLLOW, dir_fd=self.directory)
        except FileNotFoundError:
            if self.write:
                return empty
            raise Invalid("ledger disappeared")
        with os.fdopen(fd, "rb") as stream:
            regular(stream.fileno())
            raw = stream.read(MAX_METADATA + 1)
        if len(raw) > MAX_METADATA:
            raise Invalid("metadata size limit exceeded; manual review required")
        data = json.loads(raw)
        validate_data(data, self.project)
        return data

    def save(self, data):
        validate_data(data, self.project)
        raw = (json.dumps(data, sort_keys=True, indent=2) + "\n").encode()
        if len(raw) > MAX_METADATA:
            raise Invalid("metadata size limit exceeded; manual review required")
        self.validate()
        name = ".job-resources-" + secrets.token_hex(12) + ".tmp"
        try:
            fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW,
                         0o600, dir_fd=self.directory)
            with os.fdopen(fd, "wb") as stream:
                stream.write(raw)
                stream.flush()
                os.fsync(stream.fileno())
            self.validate()
            os.replace(name, "job-resources.json", src_dir_fd=self.directory,
                       dst_dir_fd=self.directory)
            os.fsync(self.directory)
            self.validate()
        finally:
            try:
                os.unlink(name, dir_fd=self.directory)  # only our unpublished metadata
            except FileNotFoundError:
                pass


def validate_data(data, project):
    if not isinstance(data, dict) or type(data.get("schema")) is not int or data.get("schema") != 1 or data.get("project") != str(project):
        raise Invalid("unknown schema or project identity; metadata preserved")
    if set(data) != {"schema", "project", "jobs", "resources"}:
        raise Invalid("unknown metadata fields; metadata preserved")
    if not isinstance(data.get("jobs"), dict) or not isinstance(data.get("resources"), dict):
        raise Invalid("invalid ledger shape; metadata preserved")
    for ident, job in data["jobs"].items():
        if not isinstance(job, dict) or not text(job.get("session")) or not text(job.get("job")):
            raise Invalid("invalid job attribution")
        if set(job) != {"session", "job", "state"}:
            raise Invalid("unknown job fields")
        if ident != key(job["session"], job["job"]) or job.get("state") not in ("active", "success", "failure"):
            raise Invalid("invalid job identity/state")
    for ident, resource in data["resources"].items():
        if not isinstance(resource, dict) or resource.get("kind") not in KINDS:
            raise Invalid("invalid resource kind")
        if set(resource) != {"kind", "resource", "purposes", "retention", "reason", "owners"}:
            raise Invalid("unknown resource fields")
        name = resource.get("resource")
        if not text(name, 4096) or ident != key(resource["kind"], name):
            raise Invalid("invalid resource identity")
        if resource["kind"] != "docker-volume" and (not Path(name).is_absolute() or str(Path(os.path.normpath(name))) != name):
            raise Invalid("invalid recorded path")
        if resource.get("retention") not in RETENTIONS or not isinstance(resource.get("purposes"), list):
            raise Invalid("invalid resource policy")
        if not resource["purposes"] or any(p not in PURPOSES for p in resource["purposes"]):
            raise Invalid("invalid resource purpose")
        if not isinstance(resource.get("owners"), list) or any(not text(o) for o in resource["owners"]):
            raise Invalid("invalid owner list")
        if not isinstance(resource.get("reason"), str) or (resource["reason"] and not text(resource["reason"])):
            raise Invalid("invalid resource reason")


def inspect_directory(project, path):
    """Never follow links; bound entry inspection; stop before project's own .git."""
    base = project / ".autodev/tmp"
    if not beneath(path, base):
        return "outside project temporary directory"
    fds = []
    try:
        fd = os.open(project, os.O_RDONLY | DIRECTORY | NOFOLLOW)
        fds.append(fd)
        for part in path.relative_to(project).parts:
            fd = os.open(part, os.O_RDONLY | DIRECTORY | NOFOLLOW, dir_fd=fd)
            fds.append(fd)
            try:
                os.stat(".git", dir_fd=fd, follow_symlinks=False)
                return "worktree marker"
            except FileNotFoundError:
                pass
        pending = [os.dup(fd)]
        count = 0
        try:
            while pending:
                current = pending.pop()
                try:
                    with os.scandir(current) as entries:
                        for entry in entries:
                            count += 1
                            if count > MAX_ENTRIES:
                                return "inspection budget exceeded"
                            if entry.name == ".git":
                                return "nested worktree marker"
                            info = entry.stat(follow_symlinks=False)
                            if info.st_dev != os.fstat(current).st_dev:
                                return "foreign filesystem"
                            if stat.S_ISLNK(info.st_mode):
                                return "symlink descendant"
                            if stat.S_ISDIR(info.st_mode):
                                child = os.open(entry.name, os.O_RDONLY | DIRECTORY | NOFOLLOW, dir_fd=current)
                                if identity(os.fstat(child)) != identity(info):
                                    os.close(child)
                                    return "directory changed during inspection"
                                pending.append(child)
                finally:
                    os.close(current)
        finally:
            for remaining in pending:
                os.close(remaining)
        return None
    except OSError:
        return "missing, unreadable or changed directory"
    finally:
        for fd in reversed(fds):
            os.close(fd)


def report(data, project):
    rows = []
    for resource in data["resources"].values():
        reasons = []
        if resource["kind"] != "directory":
            reasons.append("volumes/worktrees require manual data review")
        if resource["retention"] != "disposable":
            reasons.append("protected or reusable retention")
        if "unknown" in resource["purposes"] or "database" in resource["purposes"]:
            reasons.append("unknown or database purpose")
        if not resource["reason"]:
            reasons.append("no disposal reason")
        if not resource["owners"] or any(data["jobs"].get(o, {}).get("state") != "success" for o in resource["owners"]):
            reasons.append("active, failed or unknown owner")
        if not reasons:
            issue = inspect_directory(project, Path(resource["resource"]))
            if issue:
                reasons.append(issue)
        rows.append(dict(resource, status="protected" if reasons else "review-candidate", reasons=reasons))
    # Suppression propagates: a newly protected candidate can protect an overlap.
    changed = True
    while changed:
        changed = False
        protected = [Path(r["resource"]) for r in rows if r["kind"] != "docker-volume" and r["status"] == "protected"]
        changed_path = any(p.resolve() != p for p in protected)
        for row in rows:
            if row["status"] != "review-candidate":
                continue
            path = Path(row["resource"])
            if changed_path or any(path == p or beneath(path, p) or beneath(p, path) for p in protected):
                row["status"] = "protected"
                row["reasons"].append("protected path changed" if changed_path else "overlaps a protected recorded path")
                changed = True
    return {"resources": sorted(rows, key=lambda r: (r["kind"], r["resource"])),
            "notice": "Review hints only; declared owners cannot prove absence of live consumers. No deletion performed."}


def record(data, args, project):
    if not text(args.session) or not text(args.job) or (args.reason and not text(args.reason)):
        raise Invalid("session/job/reason must be concise printable identifiers")
    if args.kind == "docker-volume":
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,199}", args.resource):
            raise Invalid("invalid volume name")
        name = args.resource
    else:
        path = Path(args.resource)
        if not path.is_absolute():
            path = project / path
        requested_root = Path(os.path.abspath(args.project))
        if path == requested_root or beneath(path, requested_root):
            path = project / path.relative_to(requested_root)
        lexical = Path(os.path.abspath(path))
        name = str(lexical.resolve())
        if args.retention == "disposable" and (lexical != Path(name) or inspect_directory(project, lexical)):
            raise Invalid("disposable directory must be contained, readable and free of links/worktrees")
    if args.retention == "disposable" and (args.kind != "directory" or args.purpose in ("database", "unknown") or not args.reason):
        raise Invalid("disposable requires a directory, known nondatabase purpose and explicit reason")
    owner = key(args.session, args.job)
    if owner in data["jobs"] and data["jobs"][owner]["state"] != "active":
        raise Invalid("closed job cannot be reused; choose a new job identifier")
    data["jobs"][owner] = {"session": args.session, "job": args.job, "state": "active"}
    ident = key(args.kind, name)
    row = data["resources"].setdefault(ident, {"kind": args.kind, "resource": name,
        "purposes": [], "retention": args.retention, "reason": args.reason, "owners": []})
    row["retention"] = RETENTIONS[max(RETENTIONS.index(row["retention"]), RETENTIONS.index(args.retention))]
    if args.purpose not in row["purposes"]:
        row["purposes"].append(args.purpose)
    if owner not in row["owners"]:
        row["owners"].append(owner)
    if not row["reason"]:
        row["reason"] = args.reason


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, help="existing project root")
    commands = parser.add_subparsers(dest="command", required=True)
    add = commands.add_parser("record", help="attribute a resource to an active job")
    close = commands.add_parser("closeout", help="explicitly close this session/job")
    commands.add_parser("report", help="read conservative review hints; delete nothing")
    for command in (add, close):
        command.add_argument("--session", required=True)
        command.add_argument("--job", required=True)
    add.add_argument("--kind", choices=KINDS, required=True)
    add.add_argument("--resource", required=True)
    add.add_argument("--purpose", choices=PURPOSES, default="unknown")
    add.add_argument("--retention", choices=RETENTIONS, default="protected")
    add.add_argument("--reason", default="")
    close.add_argument("--outcome", choices=("success", "failure"), required=True)
    args = parser.parse_args(argv)
    try:
        project = Path(args.project).resolve(strict=True)
        with Ledger(project, args.command != "report") as ledger:
            data = ledger.load()
            if args.command == "record":
                record(data, args, project)
                ledger.save(data)
            elif args.command == "closeout":
                owner = key(args.session, args.job)
                job = data["jobs"].get(owner)
                if job is None:
                    raise Invalid("unknown session/job; cannot close another attribution")
                if job["state"] not in ("active", args.outcome):
                    raise Invalid("closed job outcome cannot change")
                if job["state"] == "active":
                    job["state"] = args.outcome
                    ledger.save(data)
            output = report(data, project)
        print(json.dumps(output, sort_keys=True))
        return 0
    except (OSError, ValueError, TypeError) as error:
        print(json.dumps({"error": str(error), "notice": "Resources preserved; inspect metadata manually."}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
