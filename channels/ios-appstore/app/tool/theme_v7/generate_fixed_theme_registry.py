#!/usr/bin/env python3
"""Generate cardock_fixed_theme_registry.dart from the V7 JSON specs."""

from __future__ import annotations
import argparse
import json
from pathlib import Path

PALETTE_FIELDS = [
    "background", "surface", "surfaceAlt", "surfaceStrong", "primary",
    "primaryPressed", "primarySoft", "textPrimary", "textSecondary",
    "textTertiary", "border", "divider", "gradientStart", "gradientMiddle",
    "gradientEnd", "calmGradientStart", "calmGradientEnd", "gradientContent",
    "shadow", "accent", "accentWarm", "surfaceElevated", "surfaceDock",
    "overlayScrim", "borderStrong", "selectedLayer", "pressedLayer",
    "disabledText", "disabledBackground", "disabledBorder", "focusRing",
    "brandContainer", "skeletonBase", "skeletonShimmer", "elevation1",
    "elevation2", "surfaceTopHighlight", "onBrandPrimary",
    "brandPrimaryContent", "brandSecondaryDecorative", "brandSecondaryContent",
    "themeDecorativeAccent", "overviewGlow", "navigationActive", "focus",
    "overviewStart", "overviewEnd", "currencyAccent", "fieldCurrency",
    "overviewTimelineAccent", "accountAccent", "accountIconBackground",
    "fieldLogin", "fieldPhone", "fieldEmail", "fieldPassword", "fieldUrl",
    "fieldSubscription", "fieldNote", "subscriptionAccent", "renewalAccent",
    "subscriptionIconBackground", "actionPrimary", "actionSecondary",
    "inputFocus", "statusNormal", "statusRenewSoon", "statusDanger",
    "statusCancelled", "statusPaused", "statusInformation",
]

def color(value: str) -> str:
    raw = value.removeprefix("#").upper()
    if len(raw) == 6:
        raw = "FF" + raw
    if len(raw) != 8:
        raise ValueError(value)
    return f"Color(0x{raw})"

def number(value: float | int) -> str:
    result = f"{float(value):.3f}".rstrip("0").rstrip(".")
    return result if "." in result else result + ".0"

def emit_profile(profile: dict, indent: str) -> list[str]:
    lines = [f"{indent}CardockMaterialProfile("]
    lines.append(f"{indent}  kind: CardockMaterialKind.{profile['kind']},")
    lines.append(f"{indent}  cardBorderWidth: {number(profile['cardBorderWidth'])},")
    lines.append(
        f"{indent}  elevatedBorderWidth: {number(profile['elevatedBorderWidth'])},"
    )
    for key in ("cardShadows", "elevatedCardShadows", "heroShadows", "dockShadows"):
        lines.append(f"{indent}  {key}: <CardockShadowSpec>[")
        for shadow in profile[key]:
            lines.extend([
                f"{indent}    CardockShadowSpec(",
                f"{indent}      color: {color(shadow['color'])},",
                f"{indent}      blurRadius: {number(shadow['blurRadius'])},",
                f"{indent}      spreadRadius: {number(shadow['spreadRadius'])},",
                f"{indent}      offset: Offset({number(shadow['dx'])}, {number(shadow['dy'])}),",
                f"{indent}    ),",
            ])
        lines.append(f"{indent}  ],")
    for key in ("surfaceHighlightOpacity", "surfaceHighlightStop"):
        lines.append(f"{indent}  {key}: {number(profile[key])},")
    for key in (
        "heroPrimaryMetricFill", "heroPrimaryMetricBorder", "heroMiniMetricFill",
        "heroMiniMetricBorder", "timelineEmphasisBorder", "lineGlowColor",
    ):
        lines.append(f"{indent}  {key}: {color(profile[key])},")
    lines.append(
        f"{indent}  heroWatermarkOpacity: {number(profile['heroWatermarkOpacity'])},"
    )
    asset = profile["textureAsset"]
    lines.append(f"{indent}  textureAsset: {repr(asset) if asset else 'null'},")
    lines.append(f"{indent}  textureOpacity: {number(profile['textureOpacity'])},")
    lines.append(f"{indent}  lineGlowBlur: {number(profile['lineGlowBlur'])},")
    lines.append(
        f"{indent}  lineDecorationOpacity: {number(profile['lineDecorationOpacity'])},"
    )
    lines.append(f"{indent}  fabElevation: {number(profile['fabElevation'])},")
    lines.append(
        f"{indent}  fabHighlightElevation: {number(profile['fabHighlightElevation'])},"
    )
    lines.append(
        f"{indent}  surfaceGradientEnabled: "
        f"{str(profile['surfaceGradientEnabled']).lower()},"
    )
    lines.append(f"{indent})")
    return lines

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokens", required=True, type=Path)
    parser.add_argument("--materials", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    token_root = json.loads(args.tokens.read_text(encoding="utf-8"))
    material_root = json.loads(args.materials.read_text(encoding="utf-8"))
    material_by_id = {item["id"]: item["profiles"] for item in material_root["families"]}

    lines = [
        "part of 'cardock_tokens.dart';", "",
        "/// Generated from spec/theme_tokens_v7.json and material_profiles_v7.json.",
        "/// Do not hand-tune values in this file without updating the JSON source.",
        "abstract final class CardockFixedThemeRegistry {",
        "  static CardockThemeSpec resolve(",
        "    CardockThemeFamily family,",
        "    Brightness brightness,",
        "  ) => switch ((family, brightness)) {",
    ]
    for family in token_root["families"]:
        family_id = family["id"]
        lines.append(
            f"    (CardockThemeFamily.{family_id}, Brightness.light) => "
            f"{family_id}Light,"
        )
        lines.append(
            f"    (CardockThemeFamily.{family_id}, Brightness.dark) => "
            f"{family_id}Dark,"
        )
    lines.extend([
        "    (CardockThemeFamily.custom, _) => throw ArgumentError(",
        "      'Custom is resolved by CardockTokens.spec, not the fixed registry.',",
        "    ),",
        "  };", "",
    ])

    for family in token_root["families"]:
        family_id = family["id"]
        for mode in ("light", "dark"):
            palette = family["palettes"][mode]
            if list(palette) != PALETTE_FIELDS:
                missing = set(PALETTE_FIELDS) - set(palette)
                extra = set(palette) - set(PALETTE_FIELDS)
                raise ValueError(
                    f"{family_id}/{mode} palette field mismatch: "
                    f"missing={missing}, extra={extra}"
                )
            name = family_id + mode.capitalize()
            lines.extend([
                f"  static const CardockThemeSpec {name} = CardockThemeSpec(",
                "    palette: CardockPalette(",
            ])
            for field in PALETTE_FIELDS:
                lines.append(f"      {field}: {color(palette[field])},")
            lines.append("    ),")
            profile_lines = emit_profile(material_by_id[family_id][mode], "    ")
            lines.append("    material: " + profile_lines[0].lstrip())
            lines.extend(profile_lines[1:-1])
            lines.append(profile_lines[-1] + ",")
            lines.extend(["  );", ""])
    lines.append("}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {args.out}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
