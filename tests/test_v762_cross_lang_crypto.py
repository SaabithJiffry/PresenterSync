"""Cross-language AES-256-GCM verification between Python, Kotlin, and AutoHotkey v2 (bcrypt.dll)."""
import atexit
import base64
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AHK_EXE = Path(r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe")
KT_TEST = ROOT / "android" / "app" / "src" / "test" / "java" / "com" / "saabithjiffry" / "presentersync" / "remote" / "AesGcmRelayCryptoTest.kt"
CRYPTO_AHK = ROOT / "Lib" / "Crypto.ahk"

_TEMP_FILES: list[Path] = []


@atexit.register
def _cleanup() -> None:
    for p in _TEMP_FILES:
        try:
            p.unlink(missing_ok=True)
        except OSError:
            pass


# --- Pure-Python AES-256-GCM (NIST SP 800-38D) ---
_SBOX = [
    0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
    0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
    0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
    0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
    0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
    0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
    0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
    0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
    0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
    0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
    0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
    0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
    0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
    0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
    0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
    0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
]
_RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]


def _xtime(a: int) -> int:
    return ((a << 1) ^ 0x1B) & 0xFF if (a & 0x80) else (a << 1)


def _aes256_key_expand(key: bytes) -> list[list[int]]:
    rk = list(key)
    for i in range(8, 60):
        t = rk[(i - 1) * 4 : i * 4]
        if i % 8 == 0:
            t = [_SBOX[t[1]] ^ _RCON[i // 8 - 1], _SBOX[t[2]], _SBOX[t[3]], _SBOX[t[0]]]
        elif i % 8 == 4:
            t = [_SBOX[b] for b in t]
        prev = rk[(i - 8) * 4 : (i - 7) * 4]
        rk.extend(prev[j] ^ t[j] for j in range(4))
    return [rk[r * 16 : (r + 1) * 16] for r in range(15)]


def _aes256_encrypt_block(block: bytes, round_keys: list[list[int]]) -> bytes:
    s = list(block)
    for i in range(16):
        s[i] ^= round_keys[0][i]
    for r in range(1, 15):
        s = [_SBOX[b] for b in s]
        s[1], s[5], s[9], s[13] = s[5], s[9], s[13], s[1]
        s[2], s[6], s[10], s[14] = s[10], s[14], s[2], s[6]
        s[3], s[7], s[11], s[15] = s[15], s[3], s[7], s[11]
        if r < 14:
            for c in range(0, 16, 4):
                a0, a1, a2, a3 = s[c], s[c + 1], s[c + 2], s[c + 3]
                t = a0 ^ a1 ^ a2 ^ a3
                s[c] ^= t ^ _xtime(a0 ^ a1)
                s[c + 1] ^= t ^ _xtime(a1 ^ a2)
                s[c + 2] ^= t ^ _xtime(a2 ^ a3)
                s[c + 3] ^= t ^ _xtime(a3 ^ a0)
        rk = round_keys[r]
        for i in range(16):
            s[i] ^= rk[i]
    return bytes(s)


def _gf_mul(x: int, y: int) -> int:
    z = 0
    v = x
    for i in range(127, -1, -1):
        if (y >> i) & 1:
            z ^= v
        lsb = v & 1
        v >>= 1
        if lsb:
            v ^= 0xE1000000000000000000000000000000
    return z


def _ghash(h_int: int, ct: bytes) -> int:
    y = 0
    for i in range(0, len(ct), 16):
        blk = ct[i : i + 16].ljust(16, b"\x00")
        y = _gf_mul(y ^ int.from_bytes(blk, "big"), h_int)
    len_blk = (0).to_bytes(8, "big") + (len(ct) * 8).to_bytes(8, "big")
    return _gf_mul(y ^ int.from_bytes(len_blk, "big"), h_int)


def aes256_gcm_encrypt(key: bytes, iv: bytes, plaintext: bytes) -> tuple[bytes, bytes]:
    rk = _aes256_key_expand(key)
    h_int = int.from_bytes(_aes256_encrypt_block(b"\x00" * 16, rk), "big")
    j0 = iv + b"\x00\x00\x00\x01"
    ctr = int.from_bytes(j0, "big")
    ct_parts = []
    for i in range(0, len(plaintext), 16):
        ctr += 1
        ks = _aes256_encrypt_block(ctr.to_bytes(16, "big"), rk)
        chunk = plaintext[i : i + 16]
        ct_parts.append(bytes(a ^ b for a, b in zip(chunk, ks)))
    ct = b"".join(ct_parts)
    tag_int = _ghash(h_int, ct) ^ int.from_bytes(_aes256_encrypt_block(j0, rk), "big")
    return ct, tag_int.to_bytes(16, "big")


def aes256_gcm_decrypt(key: bytes, iv: bytes, ct_and_tag: bytes) -> bytes:
    if len(ct_and_tag) < 16:
        raise ValueError("Ciphertext too short")
    ct, tag = ct_and_tag[:-16], ct_and_tag[-16:]
    rk = _aes256_key_expand(key)
    h_int = int.from_bytes(_aes256_encrypt_block(b"\x00" * 16, rk), "big")
    j0 = iv + b"\x00\x00\x00\x01"
    expected_tag = (_ghash(h_int, ct) ^ int.from_bytes(_aes256_encrypt_block(j0, rk), "big")).to_bytes(16, "big")
    if expected_tag != tag:
        raise ValueError("GCM auth tag mismatch")
    ctr = int.from_bytes(j0, "big")
    pt_parts = []
    for i in range(0, len(ct), 16):
        ctr += 1
        ks = _aes256_encrypt_block(ctr.to_bytes(16, "big"), rk)
        chunk = ct[i : i + 16]
        pt_parts.append(bytes(a ^ b for a, b in zip(chunk, ks)))
    return b"".join(pt_parts)


def derive_key(code: str, salt: str) -> bytes:
    return hashlib.sha256(f"PS_GCM_V1|{code.strip()}|{salt.strip()}".encode("utf-8")).digest()


def _run_ahk(script_body: str) -> str:
    fd, tmp_path = tempfile.mkstemp(suffix=".ahk", prefix="ps_xlang_")
    os.close(fd)
    p = Path(tmp_path)
    _TEMP_FILES.append(p)
    p.write_text(
        f'#Requires AutoHotkey v2.0\n#Include "{CRYPTO_AHK}"\n{script_body}\n',
        encoding="utf-8",
    )
    res = subprocess.run(
        [str(AHK_EXE), "/ErrorStdOut=UTF-8", str(p)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=5,
    )
    if res.returncode != 0:
        raise RuntimeError(f"AHK failed ({res.returncode}): {res.stderr.strip()}")
    return res.stdout.strip()


def main() -> int:
    # 1. Parse Kotlin deterministic vector and decrypt + verify in pure Python
    kt_src = KT_TEST.read_text(encoding="utf-8")
    m_code = re.search(r'VECTOR_CODE\s*=\s*"([^"]+)"', kt_src)
    m_salt = re.search(r'VECTOR_SALT\s*=\s*"([^"]+)"', kt_src)
    m_plain = re.search(r'VECTOR_PLAIN\s*=\s*"""(.*?)"""', kt_src)
    m_env = re.search(r'EXPECTED_VECTOR_ENVELOPE\s*=\s*\n?\s*"([^"]+)"', kt_src)
    assert m_code and m_salt and m_plain and m_env, "Failed to parse Kotlin test vector"

    vec_key = derive_key(m_code.group(1), m_salt.group(1))
    _, b64_iv, b64_ct_tag = m_env.group(1).split("|")
    py_dec = aes256_gcm_decrypt(vec_key, base64.b64decode(b64_iv), base64.b64decode(b64_ct_tag)).decode("utf-8")
    assert py_dec == m_plain.group(1), f"Kotlin vector mismatch: {py_dec!r}"
    print("[PASS] 1/3 Kotlin EXPECTED_VECTOR_ENVELOPE decrypted & verified in pure Python")

    # 2. AHK EncryptRelayPayload -> Python decrypt
    rand_code = "PY-AHK-" + os.urandom(4).hex()
    rand_salt = "Salt#" + os.urandom(4).hex()
    rand_plain = f'{{"msg":"hello-{os.urandom(6).hex()}","ok":true}}'
    ahk_env = _run_ahk(
        f"env := EncryptRelayPayload('{rand_plain}', '{rand_code}', '{rand_salt}')\n"
        'FileAppend(env, "*")\nExitApp(0)'
    )
    assert ahk_env.startswith("PSGCM1|"), f"Unexpected AHK envelope: {ahk_env!r}"
    _, ahk_iv_b64, ahk_ct_b64 = ahk_env.split("|")
    py_from_ahk = aes256_gcm_decrypt(
        derive_key(rand_code, rand_salt),
        base64.b64decode(ahk_iv_b64),
        base64.b64decode(ahk_ct_b64),
    ).decode("utf-8")
    assert py_from_ahk == rand_plain, f"AHK->Python mismatch: {py_from_ahk!r}"
    print("[PASS] 2/3 AHK EncryptRelayPayload -> Python AES-256-GCM decrypt verified")

    # 3. Python encrypt -> AHK DecryptRelayPayload + tampered-tag rejection
    py_iv = os.urandom(12)
    py_plain = f'{{"from":"python","n":{int.from_bytes(os.urandom(2), "big")}}}'
    py_ct, py_tag = aes256_gcm_encrypt(derive_key(rand_code, rand_salt), py_iv, py_plain.encode("utf-8"))
    py_env = "PSGCM1|" + base64.b64encode(py_iv).decode() + "|" + base64.b64encode(py_ct + py_tag).decode()

    tampered_bytes = bytearray(py_ct + py_tag)
    tampered_bytes[-1] ^= 0xFF
    tampered_env = "PSGCM1|" + base64.b64encode(py_iv).decode() + "|" + base64.b64encode(bytes(tampered_bytes)).decode()

    ahk_out = _run_ahk(
        f'dec := DecryptRelayPayload("{py_env}", "{rand_code}", "{rand_salt}")\n'
        f'bad := DecryptRelayPayload("{tampered_env}", "{rand_code}", "{rand_salt}")\n'
        'FileAppend(dec "`nBAD=" StrLen(bad), "*")\nExitApp(0)'
    )
    assert ahk_out == f"{py_plain}\nBAD=0", f"Python->AHK mismatch or tamper accepted: {ahk_out!r}"
    print("[PASS] 3/3 Python AES-256-GCM -> AHK DecryptRelayPayload + tampered-tag rejection verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
