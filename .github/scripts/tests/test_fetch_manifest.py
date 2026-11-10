"""Tests for fetch-manifest.sh with stubbed skopeo, oras and sleep.

Run: python3 -m unittest discover -s .github/scripts/tests
"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "fetch-manifest.sh")
REF = "ghcr.io/owner/img"
TAG_DIGEST = "sha256:" + "a" * 64
PINNED = "sha256:" + "b" * 64
ARTIFACT = "sha256:" + "c" * 64

SKOPEO = """#!/usr/bin/env bash
echo "skopeo $*" >> "$STUB_LOG"
printf '{"Digest": "%s"}' "$STUB_TAG_DIGEST"
"""
ORAS = """#!/usr/bin/env bash
echo "oras $*" >> "$STUB_LOG"
case "$1" in
  discover)
    if [[ "${STUB_NO_REFERRER:-}" == 1 ]]; then echo '{"referrers": []}'; else
      printf '{"referrers": [{"artifactType": "application/vnd.vespera.packages.v1+json",'
      printf ' "digest": "%s"}]}' "$STUB_ARTIFACT"
    fi ;;
  pull)
    out=""
    while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done
    echo '{}' > "$out/packages.json" ;;
esac
"""
SLEEP = "#!/usr/bin/env bash\necho \"sleep $*\" >> \"$STUB_LOG\"\n"


class FetchManifestTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.log = os.path.join(self.dir, "log")
        open(self.log, "w").close()
        for name, body in (("skopeo", SKOPEO), ("oras", ORAS), ("sleep", SLEEP)):
            path = os.path.join(self.dir, name)
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)

    def run_script(self, tag, **extra):
        env = dict(os.environ, PATH=self.dir + os.pathsep + os.environ["PATH"],
                   STUB_LOG=self.log, STUB_TAG_DIGEST=TAG_DIGEST,
                   STUB_ARTIFACT=ARTIFACT, **extra)
        p = subprocess.run(["bash", SCRIPT, REF, tag], env=env, capture_output=True,
                           text=True, check=False)
        with open(self.log) as f:
            return p, f.read()

    def test_tag_is_resolved_with_skopeo(self):
        p, log = self.run_script("testing")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn(f"skopeo inspect docker://{REF}:testing", log)
        self.assertIn(f"oras discover --format json {REF}@{TAG_DIGEST}", log)
        self.assertTrue(p.stdout.strip().endswith("packages.json"))

    def test_digest_is_used_as_given_and_never_looks_up_a_tag(self):
        p, log = self.run_script(PINNED)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertNotIn("skopeo", log)
        self.assertIn(f"oras discover --format json {REF}@{PINNED}", log)
        self.assertIn(f"oras pull --allow-path-traversal {REF}@{ARTIFACT}", log)
        self.assertTrue(p.stdout.strip().endswith("packages.json"))

    def test_malformed_digest_is_rejected(self):
        for bad in ("sha256:abc", "sha256:" + "A" * 64, "sha256:" + "g" * 64,
                    "sha256:" + "a" * 65):
            with self.subTest(bad=bad):
                p, log = self.run_script(bad)
                self.assertEqual(p.returncode, 1)
                self.assertEqual(p.stdout, "")
                self.assertIn("not a valid sha256 digest", p.stderr)
                self.assertEqual(log, "")

    def test_missing_referrer_prints_nothing_and_succeeds(self):
        p, log = self.run_script(PINNED, STUB_NO_REFERRER="1")
        self.assertEqual((p.returncode, p.stdout), (0, ""))
        self.assertEqual(log.count("oras discover"), 4)
        self.assertNotIn("skopeo", log)


if __name__ == "__main__":
    unittest.main()
