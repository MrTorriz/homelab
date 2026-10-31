#!/usr/bin/env python3
"""Check that an appdata archive holds every database dump its MANIFEST lists.

Streams the archive once, extracts only appdata/db_dumps/* into a private
temporary directory, and checks each dump without starting a database:
SQLite files must pass PRAGMA integrity_check, PostgreSQL dumps must carry
both the cluster-dump header and the "complete" trailer. Prints one JSON
line; exit 0 = all dumps intact, 1 = anything missing, empty or broken.

This proves the dumps are complete and readable, not that a restore works —
restore drills are a separate step (docs/disaster-recovery.md).
"""
import argparse
import json
import shutil
import sqlite3
import tarfile
import tempfile
from pathlib import Path

PREFIX = 'appdata/db_dumps/'


def verify_archive(archive):
    with tempfile.TemporaryDirectory(prefix='backup-integrity-') as directory:
        target = Path(directory)
        seen = set()
        with tarfile.open(archive, 'r|gz') as stream:
            for member in stream:
                name = member.name.removeprefix('./')
                if not name.startswith(PREFIX) or name == PREFIX.rstrip('/'):
                    continue
                base = Path(name).name
                if not member.isfile() or base in seen or '/' in name[len(PREFIX):]:
                    raise ValueError('unexpected or duplicate dump member: ' + base)
                seen.add(base)
                with stream.extractfile(member) as source, (target / base).open('wb') as output:
                    shutil.copyfileobj(source, output)

        manifest = target / 'MANIFEST'
        if not manifest.is_file():
            raise ValueError('archive has no dump MANIFEST')
        dumps = [line.strip() for line in manifest.read_text().splitlines() if line.strip()]
        if not dumps:
            raise ValueError('dump MANIFEST is empty')
        missing = [name for name in dumps if not (target / name).is_file() or (target / name).stat().st_size == 0]
        if missing:
            raise ValueError('missing or empty dumps: ' + ', '.join(missing))

        for name in dumps:
            file = target / name
            if name.endswith('.sqlite3'):
                connection = sqlite3.connect(file.as_uri() + '?mode=ro', uri=True)
                try:
                    if connection.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
                        raise ValueError('SQLite integrity check failed: ' + name)
                finally:
                    connection.close()
            elif name.endswith('.sql'):
                with file.open('rb') as dump:
                    header = dump.read(4096)
                    dump.seek(max(0, file.stat().st_size - 4096))
                    tail = dump.read()
                if (b'PostgreSQL database cluster dump' not in header
                        or b'PostgreSQL database cluster dump complete' not in tail):
                    raise ValueError('incomplete PostgreSQL dump: ' + name)
            else:
                raise ValueError('unknown dump type: ' + name)
    return {'state': 'ok', 'dump_count': len(dumps), 'scope': 'archive_and_dump_integrity', 'restore_tested': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify_archive(args.archive)))
        return 0
    except (OSError, ValueError, tarfile.TarError, sqlite3.Error) as error:
        # Dump contents and SQLite error text can contain private values,
        # so only our own messages are printed verbatim.
        reason = str(error) if isinstance(error, ValueError) else type(error).__name__
        print(json.dumps({'state': 'error', 'reason': reason}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
