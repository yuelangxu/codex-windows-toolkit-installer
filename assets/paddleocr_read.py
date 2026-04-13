import argparse
import json
import os
import sys
from pathlib import Path

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run PaddleOCR on an image and print JSON results."
    )
    parser.add_argument("image", help="Path to the input image.")
    parser.add_argument(
        "--lang",
        default="en",
        help="Recognition language, for example en, ch, korean, japan.",
    )
    parser.add_argument(
        "--text-only",
        action="store_true",
        help="Print only the recognized text lines.",
    )
    return parser.parse_args()


def to_serializable(value):
    try:
        import numpy as np
    except Exception:
        np = None

    if isinstance(value, dict):
        return {str(key): to_serializable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [to_serializable(item) for item in value]
    if np is not None and isinstance(value, np.ndarray):
        return value.tolist()
    if np is not None and isinstance(value, np.generic):
        return value.item()
    if isinstance(value, Path):
        return str(value)
    return value


def collect_text_lines(serialized):
    lines = []
    if isinstance(serialized, dict):
        for key, value in serialized.items():
            if key.lower() == "rec_text":
                if isinstance(value, list):
                    lines.extend(str(item) for item in value)
                else:
                    lines.append(str(value))
            else:
                lines.extend(collect_text_lines(value))
    elif isinstance(serialized, list):
        if len(serialized) == 2 and isinstance(serialized[1], list):
            candidate = serialized[1]
            if len(candidate) >= 1 and isinstance(candidate[0], str):
                lines.append(candidate[0])
                return lines
        for item in serialized:
            lines.extend(collect_text_lines(item))
    return lines


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")

    args = parse_args()
    os.environ.setdefault("PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK", "True")

    from paddleocr import PaddleOCR

    if hasattr(PaddleOCR, "predict"):
        ocr = PaddleOCR(
            lang=args.lang,
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            use_textline_orientation=False,
        )
    else:
        ocr = PaddleOCR(lang=args.lang, use_angle_cls=False, show_log=False)

    if hasattr(ocr, "predict"):
        result = ocr.predict(args.image)
    else:
        result = ocr.ocr(args.image, cls=False)

    serialized = to_serializable(result)

    if args.text_only:
        lines = collect_text_lines(serialized)
        print("\n".join(lines))
        return 0

    print(json.dumps(serialized, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
