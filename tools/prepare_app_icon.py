#!/usr/bin/env python3
"""Create iOS and Android launcher icon assets from a transparent symbol PNG."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError as error:
    raise SystemExit(
        "Pillow가 필요합니다. `python3 -m pip install Pillow`를 먼저 실행하세요."
    ) from error


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="투명 배경의 원본 심볼 PNG")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("assets/icon/generated"),
    )
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument(
        "--symbol-ratio",
        type=float,
        default=0.48,
        help="완성 아이콘에서 심볼 긴 변이 차지할 비율",
    )
    parser.add_argument(
        "--adaptive-symbol-ratio",
        type=float,
        default=0.69,
        help="Android Adaptive Icon 전경에서 심볼 긴 변이 차지할 비율",
    )
    parser.add_argument(
        "--ios-symbol-ratio",
        type=float,
        default=0.65,
        help="iOS 아이콘에서 심볼 긴 변이 차지할 비율",
    )
    parser.add_argument(
        "--offset-x-ratio",
        type=float,
        default=0.045,
        help="심볼을 오른쪽으로 이동할 캔버스 너비 비율",
    )
    parser.add_argument(
        "--offset-y-ratio",
        type=float,
        default=0.055,
        help="심볼을 아래로 이동할 캔버스 높이 비율",
    )
    parser.add_argument(
        "--ios-offset-x-ratio",
        type=float,
        default=0.035,
        help="iOS 심볼을 오른쪽으로 이동할 캔버스 너비 비율",
    )
    parser.add_argument(
        "--ios-offset-y-ratio",
        type=float,
        default=0.04,
        help="iOS 심볼을 아래로 이동할 캔버스 높이 비율",
    )
    parser.add_argument("--alpha-cutoff", type=int, default=128)
    parser.add_argument("--edge-color", default="#020B2E")
    parser.add_argument("--center-color", default="#0A205F")
    return parser.parse_args()


def hex_color(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    if len(value) != 6:
        raise ValueError(f"올바르지 않은 색상입니다: {value}")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def extract_symbol(source: Image.Image, cutoff: int) -> Image.Image:
    rgba = source.convert("RGBA")
    alpha = rgba.getchannel("A")
    mask = alpha.point(lambda value: 255 if value >= cutoff else 0)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=0.65))
    rgba.putalpha(mask)
    bounding_box = mask.getbbox()
    if bounding_box is None:
        raise ValueError("알파 임계값을 통과한 심볼을 찾지 못했습니다.")
    return rgba.crop(bounding_box)


def fit_symbol(
    symbol: Image.Image,
    size: int,
    ratio: float,
    offset_x_ratio: float,
    offset_y_ratio: float,
) -> Image.Image:
    target = round(size * ratio)
    scale = target / max(symbol.size)
    resized = symbol.resize(
        (round(symbol.width * scale), round(symbol.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    position = (
        (size - resized.width) // 2 + round(size * offset_x_ratio),
        (size - resized.height) // 2 + round(size * offset_y_ratio),
    )
    canvas.alpha_composite(resized, position)
    return canvas


def radial_background(
    size: int,
    edge: tuple[int, int, int],
    center: tuple[int, int, int],
) -> Image.Image:
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    midpoint = (size - 1) / 2
    maximum = math.sqrt(2 * midpoint * midpoint)
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - midpoint, y - midpoint) / maximum
            blend = min(1.0, distance**0.8)
            pixels[x, y] = tuple(
                round(center[channel] * (1 - blend) + edge[channel] * blend)
                for channel in range(3)
            )
    return image


def main() -> None:
    args = parse_args()
    if not 0.4 <= args.symbol_ratio <= 0.75:
        raise SystemExit("--symbol-ratio는 0.4~0.75 범위여야 합니다.")
    if not 0.6 <= args.adaptive_symbol_ratio <= 0.95:
        raise SystemExit("--adaptive-symbol-ratio는 0.6~0.95 범위여야 합니다.")
    if not 0.4 <= args.ios_symbol_ratio <= 0.75:
        raise SystemExit("--ios-symbol-ratio는 0.4~0.75 범위여야 합니다.")
    if not -0.1 <= args.offset_x_ratio <= 0.1:
        raise SystemExit("--offset-x-ratio는 -0.1~0.1 범위여야 합니다.")
    if not -0.1 <= args.offset_y_ratio <= 0.1:
        raise SystemExit("--offset-y-ratio는 -0.1~0.1 범위여야 합니다.")
    if not -0.1 <= args.ios_offset_x_ratio <= 0.1:
        raise SystemExit("--ios-offset-x-ratio는 -0.1~0.1 범위여야 합니다.")
    if not -0.1 <= args.ios_offset_y_ratio <= 0.1:
        raise SystemExit("--ios-offset-y-ratio는 -0.1~0.1 범위여야 합니다.")
    if not 1 <= args.alpha_cutoff <= 254:
        raise SystemExit("--alpha-cutoff는 1~254 범위여야 합니다.")

    source = Image.open(args.source)
    extracted = extract_symbol(source, args.alpha_cutoff)
    symbol = fit_symbol(
        extracted,
        args.size,
        args.symbol_ratio,
        args.offset_x_ratio,
        args.offset_y_ratio,
    )
    adaptive_symbol = fit_symbol(
        extracted,
        args.size,
        args.adaptive_symbol_ratio,
        args.offset_x_ratio,
        args.offset_y_ratio,
    )
    ios_symbol = fit_symbol(
        extracted,
        args.size,
        args.ios_symbol_ratio,
        args.ios_offset_x_ratio,
        args.ios_offset_y_ratio,
    )
    background = radial_background(
        args.size,
        hex_color(args.edge_color),
        hex_color(args.center_color),
    )
    completed = background.convert("RGBA")
    completed.alpha_composite(symbol)
    ios_completed = background.convert("RGBA")
    ios_completed.alpha_composite(ios_symbol)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    adaptive_symbol.save(
        args.output_dir / "app_icon_foreground.png",
        optimize=True,
    )
    completed.convert("RGB").save(
        args.output_dir / "app_icon.png",
        optimize=True,
    )
    ios_completed.convert("RGB").save(
        args.output_dir / "app_icon_ios.png",
        optimize=True,
    )
    print(f"생성 완료: {args.output_dir / 'app_icon.png'}")
    print(f"생성 완료: {args.output_dir / 'app_icon_foreground.png'}")
    print(f"생성 완료: {args.output_dir / 'app_icon_ios.png'}")


if __name__ == "__main__":
    main()
