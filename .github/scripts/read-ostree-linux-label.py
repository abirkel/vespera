#!/usr/bin/env python3
"""Print the ostree.linux config label from a `skopeo inspect --config` JSON blob on stdin.

Used by .github/workflows/check-kernel-sync.yml to compare the exact kernel-core
version two container images were built against, without pulling either image.
"""
import json
import sys

data = json.load(sys.stdin)
print(data.get("config", {}).get("Labels", {}).get("ostree.linux", ""))
