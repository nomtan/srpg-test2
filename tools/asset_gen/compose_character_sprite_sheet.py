"""Compose Blender-rendered character frames into transparent PNG sheets."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("metadata", type=Path)
    args = parser.parse_args()

    metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
    for sheet_info in metadata["sheets"]:
        cell_width, cell_height = sheet_info["cell_size"]
        columns = sheet_info["columns"]
        rows = sheet_info["rows"]
        frame_dir = Path(sheet_info["frame_dir"])
        sheet = Image.new("RGBA", (columns * cell_width, rows * cell_height), (0, 0, 0, 0))
        for direction_index, direction_name in enumerate(sheet_info["directions"]):
            for frame_index in range(columns):
                frame_path = frame_dir / f"{direction_index:02d}_{direction_name}_{frame_index:02d}.png"
                with Image.open(frame_path) as frame:
                    sheet.paste(frame.convert("RGBA"), (frame_index * cell_width, direction_index * cell_height))
        output = args.metadata.parent / sheet_info["path"]
        sheet.save(output, optimize=True)
        print(f"[sprite] wrote {output}")
        del sheet_info["frame_dir"]

    args.metadata.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
