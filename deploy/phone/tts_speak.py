#!/usr/bin/env python3
"""Kokoro TTS via sherpa-onnx.

Synthesizes speech from text, writes WAV to the given output path.

Requirements (install in Debian proot):
  pip install sherpa-onnx
  Model: ~/models/kokoro-multi-lang-v1.0/
"""

import argparse
import os
import sys


def synthesize(text, output_path, model_dir, sid=0):
    import sherpa_onnx

    tts_config = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                model=os.path.join(model_dir, "model.onnx"),
                voices=os.path.join(model_dir, "voices.bin"),
                tokens=os.path.join(model_dir, "tokens.txt"),
                data_dir=os.path.join(model_dir, "espeak-ng-data"),
                # multi-lang models need the lexicons, or generation fails
                lexicon=",".join(
                    os.path.join(model_dir, f)
                    for f in ("lexicon-us-en.txt", "lexicon-zh.txt")
                    if os.path.exists(os.path.join(model_dir, f))
                ),
                length_scale=1.0,
            ),
            num_threads=4,
        ),
    )

    tts = sherpa_onnx.OfflineTts(tts_config)
    audio = tts.generate(text, sid=sid)

    if audio.samples:
        sherpa_onnx.write_wave(output_path, audio.samples, audio.sample_rate)
        return True
    return False


def main():
    ap = argparse.ArgumentParser(description="Kokoro TTS")
    ap.add_argument("output_path", help="WAV output path")
    ap.add_argument("text", help="Text to synthesize")
    ap.add_argument(
        "--model-dir",
        default=os.path.expanduser("~/models/kokoro-multi-lang-v1.0"),
    )
    ap.add_argument("--sid", type=int, default=0, help="Speaker ID")
    args = ap.parse_args()

    if not os.path.isdir(args.model_dir):
        print(f"TTS model not found: {args.model_dir}", file=sys.stderr)
        sys.exit(1)

    ok = synthesize(args.text, args.output_path, args.model_dir, args.sid)
    if not ok:
        print("TTS produced no audio", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
