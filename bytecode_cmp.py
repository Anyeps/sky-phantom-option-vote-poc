#!/usr/bin/env python3
"""Compare deployed runtime bytecode vs locally compiled repo bytecode.

Masks CBOR metadata (trailing) and immutable slots (known addresses /
bytes32 ilk values, as 32-byte words) before comparing. Usage:
  bytecode_cmp.py <deployed.hex> <artifact.json> <imm1> [<imm2> ...]
Immutables are hex strings (0x...); addresses are matched as 32-byte
left-padded words, bytes32 values as-is.
"""
import json
import sys


def load_hex(path):
    h = open(path).read().strip()
    if h.startswith("0x"):
        h = h[2:]
    return bytes.fromhex(h)


def strip_meta(code: bytes) -> bytes:
    # Last 2 bytes = big-endian length of CBOR metadata blob.
    if len(code) < 2:
        return code
    mlen = int.from_bytes(code[-2:], "big")
    if 0 < mlen < len(code):
        return code[: -(2 + mlen)]
    return code


def mask(code: bytes, words) -> bytes:
    for w in words:
        wb = bytes.fromhex(w[2:] if w.startswith("0x") else w)
        if len(wb) == 20:  # address -> left-padded 32-byte word
            wb = b"\x00" * 12 + wb
        assert len(wb) == 32, f"immutable {w} is not 20 or 32 bytes"
        code = code.replace(wb, b"\x00" * 32)
    return code


def main():
    deployed = load_hex(sys.argv[1])
    art = json.load(open(sys.argv[2]))
    compiled = bytes.fromhex(art["deployedBytecode"]["object"][2:])
    imms = sys.argv[3:]

    d, c = strip_meta(deployed), strip_meta(compiled)
    d, c = mask(d, imms), mask(c, imms)
    print(f"deployed: {len(deployed)} bytes ({len(d)} after strip+mask)")
    print(f"compiled: {len(compiled)} bytes ({len(c)} after strip+mask)")
    if d == c:
        print("MATCH: byte-identical after stripping metadata + masking immutables")
        return 0
    # first diff
    n = min(len(d), len(c))
    for i in range(n):
        if d[i] != c[i]:
            print(f"DIFF at byte {i}: deployed {d[i]:02x} vs compiled {c[i]:02x}")
            print(f"  deployed[{max(0,i-16)}:{i+16}]: {d[max(0,i-16):i+16].hex()}")
            print(f"  compiled[{max(0,i-16)}:{i+16}]: {c[max(0,i-16):i+16].hex()}")
            break
    else:
        print(f"DIFF: common prefix identical, lengths differ ({len(d)} vs {len(c)})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
