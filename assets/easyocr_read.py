import argparse
import json
import os
import sys

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
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run EasyOCR on an image and print JSON results."
    )
    parser.add_argument("image", help="Path to the input image.")
    parser.add_argument(
        "--langs",
        default="en",
        help="Comma-separated language codes, for example en or en,zh_sim.",
    )
    parser.add_argument(
        "--gpu",
        choices=("auto", "true", "false"),
        default="auto",
        help="Use GPU when available. Default: auto.",
    )
    parser.add_argument(
        "--paragraph",
        action="store_true",
        help="Merge text boxes into paragraph output when supported.",
    )
    parser.add_argument(
        "--detail",
        type=int,
        default=1,
        choices=(0, 1),
        help="0 prints text only, 1 prints full detection data.",
    )
    return parser.parse_args()


def resolve_gpu(flag: str) -> bool:
    if flag == "true":
        return True
    if flag == "false":
        return False
    try:
        import torch

        return bool(torch.cuda.is_available())
    except Exception:
        return False


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")

    args = parse_args()
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    os.environ.setdefault("NO_ALBUMENTATIONS_UPDATE", "1")

    import easyocr

    languages = [item.strip() for item in args.langs.split(",") if item.strip()]
    if not languages:
        raise SystemExit("No valid languages were provided.")

    reader = easyocr.Reader(languages, gpu=resolve_gpu(args.gpu), verbose=False)
    result = reader.readtext(args.image, detail=args.detail, paragraph=args.paragraph)
    print(json.dumps(to_serializable(result), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
