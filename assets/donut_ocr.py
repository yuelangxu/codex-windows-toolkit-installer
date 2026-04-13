import argparse
import json
import re
import sys

from PIL import Image


PRESETS = {
    "docvqa": {
        "model": "naver-clova-ix/donut-base-finetuned-docvqa",
        "prompt_template": "<s_docvqa><s_question>{question}</s_question><s_answer>",
        "default_question": "What does this document say?",
    },
    "cord-v2": {
        "model": "naver-clova-ix/donut-base-finetuned-cord-v2",
        "prompt_template": "<s_cord-v2>",
        "default_question": None,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a Donut model on an image and print decoded JSON or text."
    )
    parser.add_argument("image", help="Path to the input image.")
    parser.add_argument(
        "--preset",
        choices=sorted(PRESETS),
        default="docvqa",
        help="Convenience preset for a known Donut task.",
    )
    parser.add_argument(
        "--model",
        help="Override the Hugging Face model id. Defaults to the preset's model.",
    )
    parser.add_argument(
        "--question",
        help="Question text for DocVQA-style models.",
    )
    parser.add_argument(
        "--task-prompt",
        help="Full task prompt override. When set, takes precedence over preset defaults.",
    )
    parser.add_argument(
        "--cpu",
        action="store_true",
        help="Force CPU execution even if CUDA is available.",
    )
    return parser.parse_args()


def build_prompt(args: argparse.Namespace, preset: dict) -> str:
    if args.task_prompt:
        return args.task_prompt

    template = preset["prompt_template"]
    if "{question}" in template:
        question = args.question or preset["default_question"] or ""
        return template.format(question=question)
    return template


def decode_result(processor, sequence: str):
    cleaned = sequence
    for token in (
        processor.tokenizer.eos_token,
        processor.tokenizer.pad_token,
    ):
        if token:
            cleaned = cleaned.replace(token, "")
    cleaned = re.sub(r"<.*?>", "", cleaned, count=1).strip()

    if hasattr(processor, "token2json"):
        try:
            return processor.token2json(cleaned)
        except Exception:
            return cleaned
    return cleaned


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")

    args = parse_args()
    preset = PRESETS[args.preset]
    model_id = args.model or preset["model"]
    task_prompt = build_prompt(args, preset)

    import torch
    from transformers import DonutProcessor, VisionEncoderDecoderModel

    processor = DonutProcessor.from_pretrained(model_id)
    model = VisionEncoderDecoderModel.from_pretrained(model_id)
    device = "cuda" if torch.cuda.is_available() and not args.cpu else "cpu"
    model.to(device)

    image = Image.open(args.image).convert("RGB")
    pixel_values = processor(image, return_tensors="pt").pixel_values.to(device)
    decoder_input_ids = processor.tokenizer(
        task_prompt, add_special_tokens=False, return_tensors="pt"
    ).input_ids.to(device)

    outputs = model.generate(
        pixel_values,
        decoder_input_ids=decoder_input_ids,
        max_length=model.decoder.config.max_position_embeddings,
        early_stopping=True,
        pad_token_id=processor.tokenizer.pad_token_id,
        eos_token_id=processor.tokenizer.eos_token_id,
        use_cache=True,
        num_beams=1,
        bad_words_ids=[[processor.tokenizer.unk_token_id]],
        return_dict_in_generate=True,
    )

    sequence = processor.batch_decode(outputs.sequences)[0]
    decoded = decode_result(processor, sequence)
    print(json.dumps(decoded, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
