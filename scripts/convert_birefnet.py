#!/usr/bin/env python3
"""Convert BiRefNet (PyTorch) to a Core ML model bundled by Peelr.

The output `BiRefNet.mlpackage` produces a single-channel foreground matte that the app
applies as alpha. Peelr also accepts a precompiled `BiRefNet.mlmodelc`; if you already have
a community-converted package, just drop it into `Resources/` and skip this script.

Usage (managed with uv; dependencies live in pyproject.toml):
    uv run scripts/convert_birefnet.py --output Resources/BiRefNet.mlpackage

Notes:
- BiRefNet is MIT-licensed (https://github.com/ZhengPeng7/BiRefNet).
- Input is a fixed 1024x1024 RGB image normalized with ImageNet mean/std.
- Output is a 1024x1024 matte in [0,1]; Peelr rescales it to the source size.
"""
import argparse
import torch
import numpy as np
import coremltools as ct
from transformers import AutoModelForImageSegmentation

IMAGE_SIZE = 1024
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]


class BiRefNetWrapper(torch.nn.Module):
    """Wrap BiRefNet so the Core ML graph takes an image and emits a single matte channel."""

    def __init__(self, model):
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1))

    def forward(self, image):
        # image: NCHW in [0,1]
        x = (image - self.mean) / self.std
        out = self.model(x)
        logits = out[-1] if isinstance(out, (list, tuple)) else out
        return torch.sigmoid(logits)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="Resources/BiRefNet.mlpackage")
    parser.add_argument("--repo", default="ZhengPeng7/BiRefNet")
    args = parser.parse_args()

    print(f"Loading {args.repo} …")
    base = AutoModelForImageSegmentation.from_pretrained(args.repo, trust_remote_code=True)
    base.eval()

    model = BiRefNetWrapper(base).eval()
    example = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE)

    print("Tracing …")
    traced = torch.jit.trace(model, example, strict=False)

    print("Converting to Core ML …")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 3, IMAGE_SIZE, IMAGE_SIZE),
            scale=1 / 255.0,
            bias=[0, 0, 0],
            color_layout=ct.colorlayout.RGB,
        )],
        outputs=[ct.TensorType(name="matte")],
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "BiRefNet foreground matte for Peelr"
    mlmodel.save(args.output)
    print(f"Saved {args.output}")


if __name__ == "__main__":
    main()
