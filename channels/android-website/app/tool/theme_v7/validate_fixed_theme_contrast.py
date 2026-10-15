#!/usr/bin/env python3
"""Recalculate rendered-surface contrast checks for all Cardock V7 themes.

This script uses only Python's standard library. It validates text, controls,
module accents, Hero overlays, semantic status colors, and Material error
foregrounds from the exact JSON specs. It does not modify app source.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class Rgba:
    red: int
    green: int
    blue: int
    alpha: int = 255

    @property
    def hex_rgb(self) -> str:
        return f"#{self.red:02X}{self.green:02X}{self.blue:02X}"


def parse_color(value: str) -> Rgba:
    raw = value.removeprefix("#")
    if len(raw) == 6:
        alpha = 255
    elif len(raw) == 8:
        alpha = int(raw[:2], 16)
        raw = raw[2:]
    else:
        raise ValueError(f"Expected #RRGGBB or #AARRGGBB, got {value!r}")
    return Rgba(
        red=int(raw[0:2], 16),
        green=int(raw[2:4], 16),
        blue=int(raw[4:6], 16),
        alpha=alpha,
    )


def alpha_blend(foreground: str, background: str, *, alpha: float | None = None) -> Rgba:
    fg = parse_color(foreground)
    bg = parse_color(background)
    fraction = fg.alpha / 255 if alpha is None else alpha
    return Rgba(
        red=round(fg.red * fraction + bg.red * (1 - fraction)),
        green=round(fg.green * fraction + bg.green * (1 - fraction)),
        blue=round(fg.blue * fraction + bg.blue * (1 - fraction)),
    )


def relative_luminance(value: str | Rgba) -> float:
    color = parse_color(value) if isinstance(value, str) else value

    def linear(channel: int) -> float:
        normalized = channel / 255
        return (
            normalized / 12.92
            if normalized <= 0.04045
            else ((normalized + 0.055) / 1.055) ** 2.4
        )

    return (
        0.2126 * linear(color.red)
        + 0.7152 * linear(color.green)
        + 0.0722 * linear(color.blue)
    )


def contrast_ratio(first: str | Rgba, second: str | Rgba) -> float:
    first_luminance = relative_luminance(first)
    second_luminance = relative_luminance(second)
    lighter = max(first_luminance, second_luminance)
    darker = min(first_luminance, second_luminance)
    return (lighter + 0.05) / (darker + 0.05)


def mix(first: str, second: str, amount: float) -> Rgba:
    left = parse_color(first)
    right = parse_color(second)
    return Rgba(
        red=round(left.red * (1 - amount) + right.red * amount),
        green=round(left.green * (1 - amount) + right.green * amount),
        blue=round(left.blue * (1 - amount) + right.blue * amount),
    )


def on_color(background: str) -> str:
    return "#FFFFFF" if contrast_ratio("#FFFFFF", background) >= 4.5 else "#101828"


def readable_color(
    source: str,
    fallback: str,
    backgrounds: Iterable[str | Rgba],
    *,
    minimum: float = 4.5,
) -> str:
    surfaces = tuple(backgrounds)
    if all(contrast_ratio(source, surface) >= minimum for surface in surfaces):
        return source
    for step in range(1, 101):
        candidate = mix(source, fallback, step / 100).hex_rgb
        if all(contrast_ratio(candidate, surface) >= minimum for surface in surfaces):
            return candidate
    return fallback


def main() -> int:
    parser = argparse.ArgumentParser()
    package_root = Path(__file__).resolve().parents[1]
    parser.add_argument(
        "--tokens",
        type=Path,
        default=package_root / "spec/theme_tokens_v7.json",
    )
    parser.add_argument(
        "--materials",
        type=Path,
        default=package_root / "spec/material_profiles_v7.json",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=package_root / "spec/contrast_validation_report.json",
    )
    args = parser.parse_args()

    token_root = json.loads(args.tokens.read_text(encoding="utf-8"))
    material_root = json.loads(args.materials.read_text(encoding="utf-8"))
    material_by_id = {
        family["id"]: family["profiles"] for family in material_root["families"]
    }
    expected_ids = [family["id"] for family in token_root["families"]]
    if expected_ids != [family["id"] for family in material_root["families"]]:
        raise ValueError("Theme-family order differs between token and material specs")

    report: dict[str, object] = {
        "schema": "cardock.fixed-theme-contrast-validation.v7",
        "method": (
            "WCAG relative luminance after alpha compositing; 43 ratio checks and "
            "1 semantic-distinctness check per palette"
        ),
        "paletteCount": 0,
        "tokensPerPalette": 71,
        "tokenValueCount": 0,
        "checksPerPalette": 44,
        "contrastChecksPerPalette": 43,
        "checkCount": 0,
        "contrastCheckCount": 0,
        "failures": [],
        "palettes": [],
        "status": "pass",
    }
    failures: list[dict[str, object]] = []
    palette_summaries: list[dict[str, object]] = []

    for family in token_root["families"]:
        family_id = family["id"]
        for mode in ("light", "dark"):
            palette: dict[str, str] = family["palettes"][mode]
            profile: dict[str, object] = material_by_id[family_id][mode]
            checks: list[dict[str, object]] = []

            def check(name: str, foreground: str | Rgba, background: str | Rgba, minimum: float) -> None:
                ratio = contrast_ratio(foreground, background)
                item = {
                    "name": name,
                    "foreground": foreground.hex_rgb if isinstance(foreground, Rgba) else foreground,
                    "background": background.hex_rgb if isinstance(background, Rgba) else background,
                    "ratio": round(ratio, 4),
                    "required": minimum,
                    "margin": round(ratio / minimum, 4),
                    "pass": ratio + 1e-9 >= minimum,
                }
                checks.append(item)
                if not item["pass"]:
                    failures.append({"family": family_id, "mode": mode, **item})

            for surface in ("background", "surface", "surfaceAlt"):
                check(f"textPrimary/{surface}", palette["textPrimary"], palette[surface], 4.5)
                check(f"textSecondary/{surface}", palette["textSecondary"], palette[surface], 4.5)
                check(f"textTertiary/{surface}", palette["textTertiary"], palette[surface], 3.0)

            for surface in ("background", "surface"):
                check(f"primary/{surface}", palette["primary"], palette[surface], 3.0)
                check(
                    f"brandSecondaryContent/{surface}",
                    palette["brandSecondaryContent"],
                    palette[surface],
                    3.0,
                )

            check(
                "navigationActive/surfaceDock",
                palette["navigationActive"],
                palette["surfaceDock"],
                3.0,
            )
            check("focusRing/surface", palette["focusRing"], palette["surface"], 3.0)
            check("actionPrimary/surface", palette["actionPrimary"], palette["surface"], 3.0)
            check("onBrandPrimary/primary", palette["onBrandPrimary"], palette["primary"], 4.5)
            check(
                "actionSecondary/surface",
                palette["actionSecondary"],
                palette["surface"],
                4.5,
            )
            check("inputFocus/surface", palette["inputFocus"], palette["surface"], 3.0)

            check("accountAccent/surface", palette["accountAccent"], palette["surface"], 3.0)
            check(
                "accountAccent/accountIconBackground",
                palette["accountAccent"],
                palette["accountIconBackground"],
                3.0,
            )
            for field in ("fieldLogin", "fieldPhone", "fieldEmail", "fieldPassword", "fieldUrl"):
                check(f"{field}/surface", palette[field], palette["surface"], 3.0)

            check(
                "subscriptionAccent/surface",
                palette["subscriptionAccent"],
                palette["surface"],
                3.0,
            )
            check(
                "subscriptionAccent/subscriptionIconBackground",
                palette["subscriptionAccent"],
                palette["subscriptionIconBackground"],
                3.0,
            )
            check("renewalAccent/surface", palette["renewalAccent"], palette["surface"], 3.0)

            for endpoint in ("overviewStart", "overviewEnd"):
                endpoint_color = palette[endpoint]
                check(
                    f"gradientContent/{endpoint}",
                    palette["gradientContent"],
                    endpoint_color,
                    4.5,
                )
                check(
                    f"gradientContent/{endpoint}/heroPrimaryMetricFill",
                    palette["gradientContent"],
                    alpha_blend(str(profile["heroPrimaryMetricFill"]), endpoint_color),
                    4.5,
                )
                check(
                    f"gradientContent/{endpoint}/heroMiniMetricFill",
                    palette["gradientContent"],
                    alpha_blend(str(profile["heroMiniMetricFill"]), endpoint_color),
                    4.5,
                )

            for status in (
                "statusNormal",
                "statusRenewSoon",
                "statusDanger",
                "statusCancelled",
                "statusPaused",
                "statusInformation",
            ):
                check(
                    f"{status}/surface",
                    palette[status],
                    palette["surface"],
                    4.5 if status == "statusDanger" else 3.0,
                )

            check(
                "onError/statusDanger",
                on_color(palette["statusDanger"]),
                palette["statusDanger"],
                4.5,
            )
            error_container = alpha_blend(
                palette["statusDanger"], palette["surface"], alpha=0.14
            )
            on_error_container = readable_color(
                palette["statusDanger"],
                palette["textPrimary"],
                (error_container,),
                minimum=4.5,
            )
            check(
                "onErrorContainer/errorContainer",
                on_error_container,
                error_container,
                4.5,
            )

            distinct = palette["statusDanger"] != palette["statusNormal"]
            distinct_item = {
                "name": "statusDanger/distinctFromStatusNormal",
                "pass": distinct,
            }
            checks.append(distinct_item)
            if not distinct:
                failures.append({"family": family_id, "mode": mode, **distinct_item})

            if len(checks) != 44:
                raise AssertionError(f"{family_id}/{mode}: expected 44 checks, got {len(checks)}")
            contrast_items = [item for item in checks if "ratio" in item]
            palette_failures = [item for item in checks if not item["pass"]]
            palette_summaries.append(
                {
                    "family": family_id,
                    "mode": mode,
                    "checks": len(checks),
                    "contrastChecks": len(contrast_items),
                    "minimumMargin": round(
                        min(float(item["margin"]) for item in contrast_items), 4
                    ),
                    "failures": len(palette_failures),
                }
            )

    palette_count = len(palette_summaries)
    report.update(
        {
            "paletteCount": palette_count,
            "tokenValueCount": palette_count * 71,
            "checkCount": palette_count * 44,
            "contrastCheckCount": palette_count * 43,
            "failures": failures,
            "palettes": palette_summaries,
            "status": "fail" if failures else "pass",
        }
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"{report['status'].upper()}: {palette_count} palettes, "
        f"{report['checkCount']} checks, {len(failures)} failures; wrote {args.out}"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
