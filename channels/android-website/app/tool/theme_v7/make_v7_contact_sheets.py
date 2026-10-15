#!/usr/bin/env python3
"""Build 16 four-page contact sheets from the V7 Flutter capture output."""

from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

THEME_LABELS = {
    "ceramicBlue": "瓷蓝晴光 Ceramic Blue",
    "sakuraMist": "樱雾柔光 Sakura Mist",
    "paperArchive": "橙墨旧刊 Paper Archive",
    "lilacMoon": "月纱丁香 Lilac Moon",
    "glacierBlue": "冰川蓝釉 Glacier Blue",
    "mistCoral": "雾海珊瑚 Mist Coral",
    "neonZero": "零域荧绿 Neon Zero",
    "obsidianGold": "曜石鎏金 Obsidian Gold",
}

def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        Path(r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc" if bold
             else "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    title_font = font(38, bold=True)
    subtitle_font = font(22)
    page_names = ["首页", "账号", "订阅", "设置"]

    written = 0
    for family_dir in sorted(p for p in args.actual.iterdir() if p.is_dir()):
        family_id = family_dir.name.split("_", 1)[1]
        label = THEME_LABELS.get(family_id, family_id)
        for mode_dir in sorted(p for p in family_dir.iterdir() if p.is_dir()):
            paths = [mode_dir / name for name in (
                "01_home.png", "02_accounts.png", "03_subscriptions.png", "04_settings.png"
            )]
            if not all(path.exists() for path in paths):
                raise FileNotFoundError(f"Incomplete capture set: {mode_dir}")
            screens = [Image.open(path).convert("RGB").resize((390, 844), Image.Resampling.LANCZOS)
                       for path in paths]
            margin, gap, header = 34, 24, 132
            width = margin * 2 + 390 * 4 + gap * 3
            height = header + 844 + 72
            canvas = Image.new("RGB", (width, height), "#F1F2F4")
            draw = ImageDraw.Draw(canvas)
            mode_cn = "浅色" if mode_dir.name == "light" else "深色"
            draw.text((margin, 25), f"{label}｜{mode_cn}模式", fill="#17191D", font=title_font)
            draw.text((margin, 78), "Cardock V7 实际 Flutter 截图｜390×844 logical / 3× PNG",
                      fill="#5E626B", font=subtitle_font)
            for index, (screen, page_name) in enumerate(zip(screens, page_names)):
                x = margin + index * (390 + gap)
                canvas.paste(screen, (x, header))
                bbox = draw.textbbox((0, 0), page_name, font=subtitle_font)
                tx = x + (390 - (bbox[2] - bbox[0])) // 2
                draw.text((tx, header + 855), page_name, fill="#31343A", font=subtitle_font)
            target = args.out / f"{family_dir.name}_{mode_dir.name}_四页联系表.png"
            canvas.save(target, optimize=True)
            written += 1

    if written != 16:
        raise RuntimeError(f"Expected 16 contact sheets, wrote {written}")
    print(f"Wrote {written} contact sheets to {args.out}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
