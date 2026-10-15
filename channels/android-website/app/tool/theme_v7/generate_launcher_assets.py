#!/usr/bin/env python3
"""Generate the eight Cardock V7 launcher palettes from the frozen Logo C art.

The script is deterministic and offline. It keeps the existing Standard icon's
geometry/alpha masks and remaps only its color roles to the authoritative V7
theme-token palette.
"""

from __future__ import annotations

import colorsys
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
TOKENS_PATH = ROOT / "tool" / "theme_v7" / "spec" / "theme_tokens_v7.json"
BRANDING_DIR = ROOT / "assets" / "branding"
RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"
FULL_TEMPLATE = BRANDING_DIR / "cardock_launcher_standard.png"
FOREGROUND_TEMPLATE = (
    RES_DIR / "drawable-xxxhdpi" / "ic_launcher_standard_foreground.png"
)

DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

FAMILIES = {
    "ceramicBlue": "ceramic_blue",
    "sakuraMist": "sakura_mist",
    "paperArchive": "paper_archive",
    "lilacMoon": "lilac_moon",
    "glacierBlue": "glacier_blue",
    "mistCoral": "mist_coral",
    "neonZero": "neon_zero",
    "obsidianGold": "obsidian_gold",
}


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    if len(value) == 8:
        value = value[2:]
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def lerp(
    first: tuple[int, int, int],
    second: tuple[int, int, int],
    amount: float,
) -> tuple[int, int, int]:
    amount = max(0.0, min(1.0, amount))
    return tuple(round(a + (b - a) * amount) for a, b in zip(first, second))


def shade(color: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, round(channel * amount))) for channel in color)


def palette_for(family: dict[str, object]) -> dict[str, tuple[int, int, int]]:
    mode = str(family["referenceMode"])
    palette = family["palettes"][mode]
    family_id = str(family["id"])
    main_start = hex_rgb(palette["gradientStart"])
    main_end = hex_rgb(palette["gradientMiddle"])
    if family_id == "neonZero":
        main_start = hex_rgb(palette["primary"])
        main_end = hex_rgb(palette["gradientEnd"])
    elif family_id == "obsidianGold":
        main_start = hex_rgb(palette["primary"])
        main_end = hex_rgb(palette["accentWarm"])
    return {
        "background": hex_rgb(palette["background"]),
        "background_alt": hex_rgb(palette["surfaceAlt"]),
        "main_start": main_start,
        "main_end": main_end,
        "secondary": hex_rgb(palette["gradientEnd"]),
        "accent": hex_rgb(palette["accent"]),
        "content": hex_rgb(palette["onBrandPrimary"]),
    }


def recolor(
    source: Image.Image,
    palette: dict[str, tuple[int, int, int]],
    *,
    full_icon: bool,
) -> Image.Image:
    image = source.convert("RGBA")
    width, height = image.size
    output = Image.new("RGBA", image.size)
    result: list[tuple[int, int, int, int]] = []
    for index, (red, green, blue, alpha) in enumerate(image.getdata()):
        if alpha == 0:
            result.append((0, 0, 0, 0))
            continue
        x = index % width
        y = index // width
        hue, saturation, value = colorsys.rgb_to_hsv(
            red / 255.0,
            green / 255.0,
            blue / 255.0,
        )
        hue *= 360.0
        position = (x / max(1, width - 1) + y / max(1, height - 1)) / 2

        if (
            not full_icon
            and 250 <= x <= 305
            and 105 <= y <= 155
            and saturation < 0.22
            and value > 0.45
        ):
            target = (255, 255, 255)
            factor = 0.92 + 0.08 * value
        elif saturation < 0.16 and value > 0.58:
            target = palette["content"]
            factor = 0.84 + 0.16 * value
        elif 32 <= hue <= 72 and saturation > 0.28:
            target = palette["accent"]
            factor = 0.78 + 0.24 * value
        elif 160 <= hue <= 210 and saturation > 0.24:
            target = palette["secondary"]
            factor = 0.76 + 0.28 * value
        elif 205 <= hue <= 300 and saturation > 0.20:
            if full_icon and value < 0.36:
                target = lerp(
                    palette["background"],
                    palette["background_alt"],
                    position,
                )
                factor = 0.90 + 0.20 * value
            else:
                target = lerp(
                    palette["main_start"],
                    palette["main_end"],
                    position,
                )
                factor = max(0.62, min(1.12, value / 0.82))
        else:
            target = lerp(
                palette["main_start"],
                palette["main_end"],
                position,
            )
            factor = 0.72 + 0.30 * value
        mapped = shade(target, factor)
        result.append((*mapped, alpha))
    output.putdata(result)
    return output


def build_full_icon(
    foreground: Image.Image,
    palette: dict[str, tuple[int, int, int]],
) -> Image.Image:
    size = 1024
    background = Image.new("RGBA", (size, size))
    pixels: list[tuple[int, int, int, int]] = []
    for y in range(size):
        for x in range(size):
            amount = (x / (size - 1) + y / (size - 1)) / 2
            pixels.append((*lerp(palette["background"], palette["background_alt"], amount), 255))
    background.putdata(pixels)

    rounded_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(rounded_mask).rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=220,
        fill=255,
    )
    output = Image.new("RGBA", (size, size))
    output.paste(background, mask=rounded_mask)

    decoration = Image.new("RGBA", (size, size))
    decoration_draw = ImageDraw.Draw(decoration)
    decoration_draw.line(
        ((80, 820), (950, 245)),
        fill=(*palette["background_alt"], 70),
        width=24,
    )
    decoration.putalpha(Image.composite(decoration.getchannel("A"), Image.new("L", (size, size)), rounded_mask))
    output.alpha_composite(decoration)
    output.alpha_composite(
        foreground.resize((size, size), Image.Resampling.LANCZOS),
    )
    return output


def round_icon(icon: Image.Image) -> Image.Image:
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, icon.width - 1, icon.height - 1), fill=255)
    rounded = Image.new("RGBA", icon.size)
    rounded.paste(icon, mask=mask)
    return rounded


def write_background(slug: str, color: tuple[int, int, int]) -> None:
    value = "#" + "".join(f"{channel:02X}" for channel in color)
    path = RES_DIR / "drawable" / f"ic_launcher_{slug}_background.xml"
    path.write_text(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<shape xmlns:android=\"http://schemas.android.com/apk/res/android\" "
        "android:shape=\"rectangle\">\n"
        f"    <solid android:color=\"{value}\" />\n"
        "</shape>\n",
        encoding="utf-8",
        newline="\n",
    )


def write_adaptive_icon(slug: str, api: int) -> None:
    monochrome = (
        "\n    <monochrome android:drawable=\"@drawable/ic_launcher_monochrome\" />"
        if api >= 33
        else ""
    )
    content = (
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<adaptive-icon xmlns:android=\"http://schemas.android.com/apk/res/android\">\n"
        f"    <background android:drawable=\"@drawable/ic_launcher_{slug}_background\" />\n"
        f"    <foreground android:drawable=\"@drawable/ic_launcher_{slug}_foreground\" />"
        f"{monochrome}\n"
        "</adaptive-icon>\n"
    )
    directory = RES_DIR / f"mipmap-anydpi-v{api}"
    for suffix in ("", "_round"):
        (directory / f"ic_launcher_{slug}{suffix}.xml").write_text(
            content,
            encoding="utf-8",
            newline="\n",
        )


def main() -> None:
    tokens = json.loads(TOKENS_PATH.read_text(encoding="utf-8"))
    source_by_id = {family["id"]: family for family in tokens["families"]}
    Image.open(FULL_TEMPLATE).close()  # Keep the frozen source-path contract.
    foreground_template = Image.open(FOREGROUND_TEMPLATE).convert("RGBA")

    for family_id, slug in FAMILIES.items():
        palette = palette_for(source_by_id[family_id])
        foreground = recolor(foreground_template, palette, full_icon=False)
        full = build_full_icon(foreground, palette)
        full.save(BRANDING_DIR / f"cardock_launcher_{slug}.png", optimize=True)

        for density, (legacy_size, foreground_size) in DENSITIES.items():
            resampling = Image.Resampling.LANCZOS
            legacy = full.resize((legacy_size, legacy_size), resampling)
            foreground_scaled = foreground.resize(
                (foreground_size, foreground_size),
                resampling,
            )
            legacy.save(
                RES_DIR / f"mipmap-{density}" / f"ic_launcher_{slug}.png",
                optimize=True,
            )
            round_icon(legacy).save(
                RES_DIR
                / f"mipmap-{density}"
                / f"ic_launcher_{slug}_round.png",
                optimize=True,
            )
            foreground_scaled.save(
                RES_DIR
                / f"drawable-{density}"
                / f"ic_launcher_{slug}_foreground.png",
                optimize=True,
            )

        write_background(slug, palette["background"])
        write_adaptive_icon(slug, 26)
        write_adaptive_icon(slug, 33)


if __name__ == "__main__":
    main()
