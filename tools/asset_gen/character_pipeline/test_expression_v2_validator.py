"""Negative tests against an actual Blender-exported channel fixture."""
import copy
from pathlib import Path
import struct
import tempfile
import unittest

from character_asset_metrics import read_glb
from validate_modular_parts import ValidationReport, _validate_expression_v2
import json

ROOT = Path(__file__).resolve().parents[3]


class ExpressionValidatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document, cls.binary = read_glb(ROOT / "artifacts/expression_v2_fixture/model.glb")

    def validate(self, mutate=None, binary=None):
        document = copy.deepcopy(self.document)
        if mutate:
            mutate(document)
        payload = json.dumps(document).encode()
        payload += b" " * (-len(payload) % 4)
        data = self.binary if binary is None else binary
        data += b"\0" * (-len(data) % 4)
        with tempfile.TemporaryDirectory(dir=ROOT / "artifacts") as folder:
            path = Path(folder) / "face/007/model.glb"
            path.parent.mkdir(parents=True)
            path.write_bytes(struct.pack("<III", 0x46546C67, 2, 28 + len(payload) + len(data)) + struct.pack("<II", len(payload), 0x4E4F534A) + payload + struct.pack("<II", len(data), 0x004E4942) + data)
            report = ValidationReport()
            _validate_expression_v2(report, path, False)
            return {c["code"] for c in report.checks if c["status"] == "FAIL"}

    def test_valid_blender_channels(self):
        self.assertEqual(self.validate(), set())

    def test_missing_uv(self):
        self.assertIn("face.expression.channels", self.validate(lambda d: d["meshes"][0]["primitives"][0]["attributes"].pop("TEXCOORD_1")))

    def test_missing_mask(self):
        self.assertIn("face.expression.channels", self.validate(lambda d: d["meshes"][0]["primitives"][0]["attributes"].pop("COLOR_0")))

    def test_unclassified_material(self):
        self.assertIn("face.expression.materials", self.validate(lambda d: d["materials"][0].update(name="Unknown")))

    def test_nonfinite_uv(self):
        attribute = self.document["meshes"][0]["primitives"][0]["attributes"]["TEXCOORD_1"]
        accessor = self.document["accessors"][attribute]
        view = self.document["bufferViews"][accessor["bufferView"]]
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        data = bytearray(self.binary)
        struct.pack_into("<f", data, offset, float("nan"))
        self.assertIn("face.expression.uv", self.validate(binary=bytes(data)))


if __name__ == "__main__":
    unittest.main()
