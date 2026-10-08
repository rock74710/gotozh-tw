#!/usr/bin/env python3
"""標準庫 CLI journey: TTY、JSON、錯誤狀態與不改寫輸入檔。"""

from __future__ import annotations

import argparse
import errno
import json
import os
import pty
import select
import subprocess
import tempfile
import time
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run_cli(binary: Path, *args: str, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [str(binary), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def check_pty_journey(binary: Path) -> None:
    master, slave = pty.openpty()
    require(os.isatty(master) and os.isatty(slave), "PTY 測試端點必須是真正的 TTY。")
    process = subprocess.Popen(
        [str(binary), "convert"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)

    source = "😀視頻 文件夾 股票代碼 全屏 外屏 內屏 摺疊屏"
    source_bytes = source.encode("utf-8")
    os.write(master, source_bytes + b"\n")
    captured = bytearray()
    input_deadline = time.monotonic() + 3
    while time.monotonic() < input_deadline and (source_bytes not in captured or b"\n" not in captured):
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(master, 8192)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            captured.extend(chunk)
    require(source_bytes in captured and b"\n" in captured, "PTY 應回顯完整可見的使用者輸入。")
    time.sleep(0.5)

    os.write(master, b"\x04")
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(master, 8192)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            captured.extend(chunk)
        if process.poll() is not None and not ready:
            break

    try:
        process.wait(timeout=max(0.1, deadline - time.monotonic()))
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        raise AssertionError(f"CLI 在 PTY 輸入結束後沒有退出：{bytes(captured)!r}")
    os.close(master)
    output = bytes(captured).decode("utf-8", errors="replace")
    require(process.returncode == 0, f"PTY CLI 應以 0 結束，實際為 {process.returncode}: {output}")
    require("😀影片 資料夾 股票代碼 全螢幕 外螢幕 內螢幕 摺疊螢幕" in output, "PTY 應顯示轉換輸出，且保留情境詞。")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="已建置的 gotozh 執行檔路徑")
    args = parser.parse_args()
    binary = args.binary.expanduser().resolve()
    require(binary.is_file() and os.access(binary, os.X_OK), f"找不到可執行檔：{binary}")

    help_result = run_cli(binary, "--help")
    require(help_result.returncode == 0 and b"gotozh" in help_result.stdout, "--help 應成功並顯示用法。")

    with tempfile.TemporaryDirectory(prefix="gotozh-pty-check-") as directory:
        input_path = Path(directory) / "sample.txt"
        original = "😀視頻\n代碼 文件夾".encode("utf-8")
        input_path.write_bytes(original)

        converted = run_cli(binary, "convert", str(input_path))
        require(converted.returncode == 0, f"檔案轉換應成功：{converted.stderr.decode('utf-8', 'replace')}")
        require(converted.stdout.decode("utf-8") == "😀影片\n代碼 資料夾", "檔案轉換應略過情境詞並保留換行。")
        require(input_path.read_bytes() == original, "convert 不得改寫輸入檔。")

        scanned = run_cli(binary, "scan", str(input_path))
        require(scanned.returncode == 0, f"JSON 掃描應成功：{scanned.stderr.decode('utf-8', 'replace')}")
        payload = json.loads(scanned.stdout)
        require(payload["sourceUTF16Length"] == 11, "JSON 全文長度應使用 UTF-16。")
        positions = [(item["from"], item["startUTF16"], item["endUTF16"]) for item in payload["occurrences"]]
        require(positions == [("視頻", 2, 4), ("代碼", 5, 7), ("文件夾", 8, 11)], "JSON 詞彙位置應使用 UTF-16 半開區間。")
        require(input_path.read_bytes() == original, "scan 不得改寫輸入檔。")

        bad_path = Path(directory) / "invalid.txt"
        invalid_bytes = b"\xc3("
        bad_path.write_bytes(invalid_bytes)
        invalid = run_cli(binary, "convert", str(bad_path))
        require(invalid.returncode != 0 and invalid.stderr, "無效 UTF-8 應寫錯誤到 stderr 並以非零結束。")
        require(bad_path.read_bytes() == invalid_bytes, "UTF-8 錯誤時不得改寫輸入檔。")

    bad_arguments = run_cli(binary, "unknown")
    require(bad_arguments.returncode == 2 and bad_arguments.stderr, "未知參數應寫 stderr 並以狀態 2 結束。")
    check_pty_journey(binary)
    print("CLI PTY、JSON、錯誤狀態與檔案保護驗收通過。")


if __name__ == "__main__":
    main()
