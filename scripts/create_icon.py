"""Generate the small built-in development icon without external packages."""

import struct
import zlib
from pathlib import Path


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


size = 256
letter = [
    "0111110",
    "1100011",
    "1100000",
    "0111100",
    "0000110",
    "1100011",
    "0111110",
]
pixels = bytearray()
for y in range(size):
    pixels.append(0)
    for x in range(size):
        dx, dy = x - 128, y - 128
        if dx * dx + dy * dy < 118 * 118:
            color = (30, 88, 189, 255)
            letter_x, letter_y = (x - 44) // 13, (y - 46) // 23
            if 0 <= letter_x < 7 and 0 <= letter_y < 7 and letter[letter_y][letter_x] == "1":
                color = (255, 255, 255, 255)
        else:
            color = (0, 0, 0, 0)
        pixels.extend(color)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(pixels), 9))
png += chunk(b"IEND", b"")
output = Path(__file__).resolve().parent.parent / "src-tauri/icons/icon.png"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(png)
