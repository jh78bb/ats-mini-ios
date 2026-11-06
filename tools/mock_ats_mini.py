#!/usr/bin/env python3
"""
모의 ATS Mini (펌웨어 v2.45 "Ad hoc" 원격 제어 프로토콜, TCP).

iOS 시뮬레이터에는 블루투스가 없어서, 실제 수신기 대신 이 서버에 Wi-Fi TCP로 연결해
앱을 끝까지 시험할 수 있습니다. 앱의 `기기 연결 → Wi-Fi TCP`에서 호스트 127.0.0.1, 포트 60000으로 연결하세요.

펌웨어 소스(ats-mini/Remote.cpp, ParserAdhoc.cpp, Memories.cpp, Menu.cpp)에서 읽은 동작을 따릅니다.
  - 입력 프레이밍: `F`, `#`는 CR/LF까지, 나머지는 한 글자씩 즉시 실행
  - `F`, `#` 입력은 글자 그대로 되돌려 보냅니다(에코)
  - 오류는 "\\r\\nError: ...\\r\\n"
  - `t`로 켜는 상태 줄(0.5초마다, 15개 필드) 형식과 28개 밴드 표
  - 메모리 슬롯 99개와 `#` 검증 규칙(밴드 이름, 주파수 범위, FM 여부)

이 서버는 실제 수신기를 대신하는 것이 아니라 앱의 동작을 시험하기 위한 도구입니다. 실제 펌웨어와 다를 수 있습니다.

사용법:
    python3 tools/mock_ats_mini.py            # 127.0.0.1:60000
    python3 tools/mock_ats_mini.py -v         # 받은 명령을 출력
    python3 tools/mock_ats_mini.py --no-f     # F 명령이 없는 펌웨어처럼 동작(앱의 엔코더 대체 경로 시험)
    python3 tools/mock_ats_mini.py --drop-memory-write   # '#'를 받고도 저장하지 않음(앱의 저장 실패 안내 시험)
"""
import argparse
import asyncio
import random

VER_APP = 245
MAX_BFO = 16000  # SSB 튜닝 격자 = 2 * MAX_BFO

# (이름, 최소 Hz, 최대 Hz, 기본 Hz, 기본 모드) - 펌웨어 Menu.cpp의 bands[] 순서
BANDS = [
    ("VHF", 64_000_000, 108_000_000, 103_900_000, "FM"),
    ("ALL", 150_000, 30_000_000, 15_000_000, "AM"),
    ("11M", 25_600_000, 26_100_000, 25_850_000, "AM"),
    ("13M", 21_500_000, 21_900_000, 21_650_000, "AM"),
    ("15M", 18_900_000, 19_100_000, 18_950_000, "AM"),
    ("16M", 17_400_000, 18_100_000, 17_650_000, "AM"),
    ("19M", 15_100_000, 15_900_000, 15_450_000, "AM"),
    ("22M", 13_500_000, 13_900_000, 13_650_000, "AM"),
    ("25M", 11_000_000, 13_000_000, 11_850_000, "AM"),
    ("31M", 9_000_000, 11_000_000, 9_650_000, "AM"),
    ("41M", 7_000_000, 9_000_000, 7_300_000, "AM"),
    ("49M", 5_000_000, 7_000_000, 6_000_000, "AM"),
    ("60M", 4_000_000, 5_100_000, 4_950_000, "AM"),
    ("75M", 3_500_000, 4_000_000, 3_950_000, "AM"),
    ("90M", 3_000_000, 3_500_000, 3_300_000, "AM"),
    ("MW3", 1_700_000, 3_500_000, 2_500_000, "AM"),
    ("MW2", 495_000, 1_701_000, 783_000, "AM"),
    ("MW1", 150_000, 1_800_000, 810_000, "AM"),
    ("160M", 1_800_000, 2_000_000, 1_900_000, "LSB"),
    ("80M", 3_500_000, 4_000_000, 3_800_000, "LSB"),
    ("40M", 7_000_000, 7_300_000, 7_150_000, "LSB"),
    ("30M", 10_000_000, 10_200_000, 10_125_000, "LSB"),
    ("20M", 14_000_000, 14_400_000, 14_100_000, "USB"),
    ("17M", 18_000_000, 18_200_000, 18_115_000, "USB"),
    ("15M", 21_000_000, 21_500_000, 21_225_000, "USB"),
    ("12M", 24_800_000, 25_000_000, 24_940_000, "USB"),
    ("10M", 28_000_000, 29_700_000, 28_500_000, "USB"),
    ("CB", 25_000_000, 28_000_000, 27_135_000, "AM"),
]
MODES = ["FM", "LSB", "USB", "AM"]  # bandModeDesc
STEPS = {"FM": ["50k", "100k", "200k"], "AM": ["1k", "5k", "9k", "10k"], "SSB": ["10", "25", "50", "100", "500", "1k"]}
BANDWIDTHS = {"FM": ["Auto", "110k", "84k", "60k", "40k"], "AM": ["6k", "4k", "3k", "2k", "1k", "1.8k", "2.5k"],
              "SSB": ["1.2k", "2.2k", "3k", "4k", "0.5k", "1.0k"]}

# 시험용 가짜 방송국 (Hz, 최고 RSSI dBµV, 폭 Hz). Seek/Scan 시험에 씁니다.
STATIONS = [
    (89_100_000, 50, 60_000), (93_100_000, 45, 60_000), (95_900_000, 24, 60_000),
    (101_700_000, 52, 60_000), (107_700_000, 40, 60_000),
    (1_134_000, 42, 6_000), (774_000, 32, 6_000),
    (9_620_000, 36, 6_000), (5_985_000, 30, 6_000),
]


def kind(mode):
    return "FM" if mode == "FM" else ("SSB" if mode in ("LSB", "USB") else "AM")


class Radio:
    def __init__(self, args):
        self.args = args
        self.band = 0
        self.freq = {i: b[3] for i, b in enumerate(BANDS)}
        self.mode = {i: b[4] for i, b in enumerate(BANDS)}
        self.step = {i: (1 if b[4] == "FM" else 1) for i, b in enumerate(BANDS)}
        self.bw = {i: 0 for i in range(len(BANDS))}
        self.agc, self.volume, self.sleep, self.seq = 0, 24, False, 0
        self.memories = {1: [0, 89_100_000, "FM", "Classic"], 2: [0, 107_700_000, "FM", ""]}
        self.log_on = False

    # 현재 상태
    @property
    def cur_mode(self): return self.mode[self.band]
    @property
    def cur_freq(self): return self.freq[self.band]
    def step_desc(self): return STEPS[kind(self.cur_mode)][min(self.step[self.band], len(STEPS[kind(self.cur_mode)]) - 1)]
    def bw_desc(self): return BANDWIDTHS[kind(self.cur_mode)][min(self.bw[self.band], len(BANDWIDTHS[kind(self.cur_mode)]) - 1)]

    def step_hz(self):
        d = self.step_desc()
        return int(float(d[:-1]) * 1000) if d.endswith("k") else int(d)

    def set_freq(self, hz):
        """updateFrequency: 범위 밖이면 False. FM은 10 kHz, AM은 1 kHz 격자에 맞춥니다."""
        lo, hi = BANDS[self.band][1], BANDS[self.band][2]
        if hz < lo or hz > hi:
            return False
        k = kind(self.cur_mode)
        if k == "FM": hz = round(hz / 10_000) * 10_000
        elif k == "AM": hz = round(hz / 1000) * 1000
        self.freq[self.band] = hz
        return True

    def signal(self):
        hz = self.cur_freq
        noise = 6 + random.random() * 2
        best = noise
        for f, peak, width in STATIONS:
            d = abs(hz - f)
            if d < width:
                best = max(best, noise + (peak - noise) * (1 - d / width))
        rssi = int(best)
        return rssi, int(max(0, (rssi - 5) * 0.5))

    def status_line(self):
        rssi, snr = self.signal()
        hz, mode = self.cur_freq, self.cur_mode
        if mode == "FM": f, bfo = hz // 10_000, 0
        elif mode == "AM": f, bfo = hz // 1000, 0
        else:
            grid = ((hz + MAX_BFO) // (2 * MAX_BFO)) * (2 * MAX_BFO)
            f, bfo = grid // 1000, hz - grid
        self.seq = (self.seq + 1) % 256
        return (f"{VER_APP},{f},{bfo},0,{BANDS[self.band][0]},{mode},{self.step_desc()},{self.bw_desc()},"
                f"{self.agc},{self.volume},{rssi},{snr},{100 + self.band},{4.05 + random.random() * 0.02:.2f},{self.seq}\r\n")


def is_newline(b): return b in (0x0A, 0x0D)


class Session:
    def __init__(self, radio, writer, verbose):
        self.radio, self.writer, self.verbose = radio, writer, verbose
        self.buf = bytearray()

    def write(self, text):
        self.writer.write(text if isinstance(text, bytes) else text.encode())

    def error(self, message):
        self.write(f"\r\nError: {message}\r\n")

    # --- 입력: 펌웨어 frameAdhoc + remoteEchoInput를 그대로 흉내 냅니다
    def feed(self, byte):
        a = self.radio.args
        multi = (not a.no_f) and (self.buf[0] if self.buf else byte) in (ord("#"), ord("F"))
        if multi and not is_newline(byte):
            self.write(bytes([byte]))   # 에코
        self.buf.append(byte)
        first = self.buf[0]
        if multi:
            if not is_newline(byte): return
            frame = bytes(self.buf); self.buf.clear()
            self.handle_long(frame)
            return
        if is_newline(first):
            self.buf.clear()
            return
        frame = bytes(self.buf); self.buf.clear()
        self.handle_short(chr(frame[0]))

    def handle_long(self, frame):
        r = self.radio
        text = frame.rstrip(b"\r\n").decode("ascii", "replace")
        if self.verbose: print("<-", repr(text))
        if text[0] == "F":
            if len(text) == 1: return self.error("Invalid command syntax")
            digits = text[1:]
            if not digits.isdigit() or int(digits) == 0 or int(digits) > 0xFFFFFFFF:
                return self.error("Invalid command argument")
            self.write("\r\n")
            if not r.set_freq(int(digits)):
                self.error("Frequency is out of range for the current band")
            return
        # '#slot,band,freq,mode[,name]'
        fields = text[1:].split(",", 4)
        if len(fields) < 4: return self.error("Invalid command syntax")
        slot_s, band, freq_s, mode = fields[0], fields[1], fields[2], fields[3]
        has_name, name = len(fields) == 5, (fields[4] if len(fields) == 5 else "")
        if not slot_s.isdigit() or int(slot_s) == 0 or not freq_s.isdigit(): return self.error("Invalid command argument")
        if not band or not mode: return self.error("Invalid command syntax")
        if has_name and any(ord(c) < 0x20 or ord(c) > 0x7E for c in name): return self.error("Invalid command argument")
        self.write("\r\n")
        slot, freq = int(slot_s), int(freq_s)
        if slot < 1 or slot > 99: return self.error("Invalid memory slot number")
        if mode not in MODES: return self.error("No such mode")
        known, found = False, None
        for i, b in enumerate(BANDS):
            if b[0] != band: continue
            known = True
            fm_ok = (mode == "FM") == (b[4] == "FM")
            if freq == 0 or (b[1] <= freq <= b[2] and fm_ok):
                found = i
                break
        if found is None: return self.error("Invalid frequency or mode" if known else "No such band")
        if r.args.drop_memory_write: return   # 시험용: 받고도 저장하지 않음
        old = r.memories.get(slot, [found, 0, mode, ""])
        r.memories[slot] = [found, freq, mode, name[:9] if has_name else old[3]]

    def handle_short(self, c):
        r = self.radio
        if self.verbose: print("<-", repr(c))
        k = kind(r.cur_mode)
        if c in "Rr":
            hz = r.cur_freq + (1 if c == "R" else -1) * r.step_hz()
            lo, hi = BANDS[r.band][1], BANDS[r.band][2]
            r.set_freq(lo if hz > hi else hi if hz < lo else hz)
        elif c in "Bb":
            r.band = (r.band + (1 if c == "B" else -1)) % len(BANDS)
        elif c in "Mm":
            if BANDS[r.band][4] != "FM" or r.cur_mode != "FM":
                order = ["AM", "LSB", "USB"]
                i = order.index(r.cur_mode) if r.cur_mode in order else 0
                r.mode[r.band] = order[(i + (1 if c == "M" else -1)) % 3]
        elif c in "Ss":
            n = len(STEPS[k]); r.step[r.band] = (r.step[r.band] + (1 if c == "S" else -1)) % n
        elif c in "Ww":
            n = len(BANDWIDTHS[k]); r.bw[r.band] = (r.bw[r.band] + (1 if c == "W" else -1)) % n
        elif c in "Aa":
            r.agc = max(0, min(27, r.agc + (1 if c == "A" else -1)))
        elif c in "Vv":
            r.volume = max(0, min(63, r.volume + (1 if c == "V" else -1)))
        elif c == "O": r.sleep = True
        elif c == "o": r.sleep = False
        elif c == "t": r.log_on = not r.log_on
        elif c == "$":
            for n in sorted(r.memories):
                b, freq, mode, name = r.memories[n]
                if freq:
                    self.write(f"#{n:02d},{BANDS[b][0]},{freq},{mode}{',' if name else ''}{name}\r\n")
        # e E L l I i C c T @ ^ 등은 이 모의 서버에서 아무 일도 하지 않습니다


async def main():
    ap = argparse.ArgumentParser(description="모의 ATS Mini (TCP, Ad hoc 프로토콜)")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=60000)
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--no-f", action="store_true", help="F, # 명령이 없는 오래된 펌웨어처럼 동작")
    ap.add_argument("--drop-memory-write", action="store_true", help="'#'를 받고도 저장하지 않음")
    args = ap.parse_args()
    radio = Radio(args)

    async def client(reader, writer):
        s = Session(radio, writer, args.verbose)
        print("연결됨:", writer.get_extra_info("peername"))

        async def ticker():
            while True:
                await asyncio.sleep(0.5)
                if radio.log_on and not s.buf:
                    s.write(radio.status_line())
                    await writer.drain()
        task = asyncio.create_task(ticker())
        try:
            while data := await reader.read(256):
                for b in data:
                    s.feed(b)
                await writer.drain()
        except (ConnectionError, asyncio.CancelledError):
            pass
        finally:
            task.cancel()
            writer.close()
            print("연결 종료")

    server = await asyncio.start_server(client, args.host, args.port)
    print(f"모의 ATS Mini: {args.host}:{args.port}  (Ctrl+C로 종료)"
          + ("  [--no-f]" if args.no_f else "") + ("  [--drop-memory-write]" if args.drop_memory_write else ""))
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
