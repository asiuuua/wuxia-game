# tools/gen_ui_sfx.py
# 合成占位 UI 音效（纯标准库，无需第三方依赖），写入 resources/audio/sfx/
# 设计：短促正弦/三角音 + 快起快落包络，区分 hover/click/confirm/cancel/back/open/close/error。
# 这是占位音频；正式音效请替换为真实 .wav 并保留同名，配置表 data/configs/ui/ui_sfx.json 无需改动。

import math
import struct
import wave
import os

SR = 44100  # 采样率

def _note(freq, dur_ms, amp=0.4, wave_type="sine"):
    """生成单个音的 float 样本列表（[-1,1]）。"""
    n = int(SR * dur_ms / 1000.0)
    out = []
    for i in range(n):
        t = i / SR
        phase = 2.0 * math.pi * freq * t
        if wave_type == "sine":
            s = math.sin(phase)
        elif wave_type == "tri":
            s = 2.0 * abs(2.0 * (freq * t - math.floor(freq * t + 0.5))) - 1.0
        elif wave_type == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
        else:
            s = math.sin(phase)
        out.append(s * amp)
    return out

def _envelope(samples, attack_ms=4.0, release_ms=12.0):
    """快起快落包络，避免爆音。"""
    a = int(SR * attack_ms / 1000.0)
    r = int(SR * release_ms / 1000.0)
    n = len(samples)
    out = []
    for i, s in enumerate(samples):
        g = 1.0
        if i < a:
            g = i / max(1, a)
        elif i > n - r:
            g = max(0.0, (n - i) / max(1, r))
        out.append(s * g)
    return out

def _seq(notes):
    """把多个 (freq, dur_ms, amp, type) 串成一段。"""
    out = []
    for freq, dur_ms, amp, wtype in notes:
        out.extend(_envelope(_note(freq, dur_ms, amp, wtype)))
    return out

def _write(path, samples, amp_clip=0.7):
    # 限幅后转 16-bit PCM
    pcm = bytearray()
    for s in samples:
        v = max(-1.0, min(1.0, s / amp_clip))
        iv = int(v * 32767.0)
        pcm += struct.pack("<h", iv)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(pcm))

def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "resources", "audio", "sfx")
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    specs = {
        # 悬停 / 选择高亮：清亮短促高音 blip
        "ui_hover.wav":  _seq([(1046.5, 55, 0.35, "sine")]),
        # 点击：中频短促
        "ui_click.wav":  _seq([(660.0, 45, 0.40, "sine")]),
        # 确认：上行两音（C5->G5）
        "ui_confirm.wav": _seq([(523.25, 70, 0.40, "tri"), (783.99, 110, 0.40, "tri")]),
        # 取消：下行低音
        "ui_cancel.wav": _seq([(392.0, 70, 0.40, "tri"), (261.63, 110, 0.40, "tri")]),
        # 返回：单音柔和
        "ui_back.wav":   _seq([(523.25, 70, 0.32, "sine")]),
        # 打开：上行
        "ui_open.wav":   _seq([(440.0, 80, 0.38, "tri"), (660.0, 120, 0.38, "tri")]),
        # 关闭：下行
        "ui_close.wav":  _seq([(660.0, 80, 0.38, "tri"), (440.0, 120, 0.38, "tri")]),
        # 错误：低频方波嗡鸣
        "ui_error.wav":  _seq([(160.0, 200, 0.45, "square")]),
    }

    for name, samples in specs.items():
        p = os.path.join(out_dir, name)
        _write(p, samples)
        size = os.path.getsize(p)
        print(f"WROTE {name}  ({size} bytes)")

    print("DONE")

if __name__ == "__main__":
    main()
