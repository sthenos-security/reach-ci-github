#!/usr/bin/env python3
"""Select committable paths and write a NUL-delimited pathspec file."""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    candidate_list = Path(sys.argv[1])
    stage_list = Path(sys.argv[2])
    raw = candidate_list.read_bytes().split(b"\0")
    keep: list[str] = []
    for item in raw:
        if not item:
            continue
        path = item.decode("utf-8", "surrogateescape")
        name = path.rsplit("/", 1)[-1]
        if (
            path == ".reachable"
            or path.startswith(".reachable/")
            or path.endswith(".sarif")
            or name.startswith("reachable-")
        ):
            continue
        keep.append(path)

    if keep:
        stage_list.write_bytes(
            b"\0".join(p.encode("utf-8", "surrogateescape") for p in sorted(keep)) + b"\0"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
