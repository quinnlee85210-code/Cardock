#!/usr/bin/env python3
"""Audit Cardock's generated offline brand catalog without third-party modules."""

from __future__ import annotations

import json
import struct
import sys
import zlib
from collections import defaultdict
from pathlib import Path

import generate_brand_catalog as generator


MAX_BUNDLED_BYTES = 5 * 1024 * 1024
RUNTIME_FIELDS = {
    "brandId", "canonicalName", "aliases", "ambiguousAliases", "categories",
    "regions", "assetPath", "assetFormat", "renderMode", "brandColor",
    "opticalScale", "minimumRenderableDp", "monogramText", "sourceKind",
    "trademarkAuthorization",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"Expected JSON object: {path}")
    return value


def paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def decode_rgba_png(path: Path) -> tuple[int, int, bytes]:
    payload = path.read_bytes()
    require(payload.startswith(b"\x89PNG\r\n\x1a\n"), f"Not PNG: {path}")
    offset = 8
    header: tuple[int, int, int, int, int, int, int] | None = None
    compressed = bytearray()
    while offset < len(payload):
        require(offset + 12 <= len(payload), f"Truncated PNG chunk: {path}")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        kind = payload[offset + 4 : offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        require(data_end + 4 <= len(payload), f"Truncated PNG data: {path}")
        data = payload[data_start:data_end]
        expected_crc = struct.unpack(">I", payload[data_end : data_end + 4])[0]
        require(
            zlib.crc32(kind + data) & 0xFFFFFFFF == expected_crc,
            f"PNG CRC mismatch: {path}",
        )
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", data)
        elif kind == b"IDAT":
            compressed.extend(data)
        elif kind == b"IEND":
            break
        offset = data_end + 4

    require(header is not None, f"PNG missing IHDR: {path}")
    width, height, bit_depth, color_type, compression, filtering, interlace = header
    require(bit_depth == 8, f"PNG must use 8-bit channels: {path}")
    require(color_type == 6, f"PNG must be RGBA for transparency: {path}")
    require(compression == 0 and filtering == 0 and interlace == 0, f"Unsupported PNG encoding: {path}")
    raw = zlib.decompress(bytes(compressed))
    bytes_per_pixel = 4
    stride = width * bytes_per_pixel
    require(len(raw) == height * (stride + 1), f"PNG scanline size mismatch: {path}")
    rows: list[bytearray] = []
    position = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = raw[position]
        position += 1
        source = raw[position : position + stride]
        position += stride
        row = bytearray(stride)
        for index, byte in enumerate(source):
            left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            above = previous[index]
            upper_left = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            if filter_type == 0:
                value = byte
            elif filter_type == 1:
                value = byte + left
            elif filter_type == 2:
                value = byte + above
            elif filter_type == 3:
                value = byte + ((left + above) // 2)
            elif filter_type == 4:
                value = byte + paeth(left, above, upper_left)
            else:
                raise ValueError(f"Unsupported PNG filter {filter_type}: {path}")
            row[index] = value & 0xFF
        rows.append(row)
        previous = row
    return width, height, b"".join(rows)


def audit_png(path: Path) -> dict:
    width, height, pixels = decode_rgba_png(path)
    require((width, height) == (96, 96), f"Asset must be 96x96: {path}")
    visible: list[tuple[int, int]] = []
    for index in range(0, len(pixels), 4):
        red, green, blue, alpha = pixels[index : index + 4]
        if alpha:
            require(red == green == blue, f"Asset is not monochrome: {path}")
            pixel_index = index // 4
            visible.append((pixel_index % width, pixel_index // width))
    require(len(visible) >= 8, f"Asset has no meaningful glyph: {path}")
    corner_indexes = (0, width - 1, (height - 1) * width, width * height - 1)
    require(
        all(pixels[index * 4 + 3] == 0 for index in corner_indexes),
        f"Asset background is not transparent: {path}",
    )
    xs = [value[0] for value in visible]
    ys = [value[1] for value in visible]
    return {
        "width": width,
        "height": height,
        "visiblePixelCount": len(visible),
        "visibleBounds": [min(xs), min(ys), max(xs), max(ys)],
    }


def audit() -> dict:
    seeds, _, evidence = generator.load_and_verify_sources()
    normalization_source = generator.load_and_verify_unorm_source()
    master = read_json(generator.MASTER_PATH)
    runtime = read_json(generator.RUNTIME_PATH)
    validation = read_json(generator.VALIDATION_PATH)
    parity_result = read_json(generator.NORMALIZATION_PARITY_PATH)
    entries = master.get("brands")
    runtime_entries = runtime.get("brands")
    require(master.get("schemaVersion") == 1, "Master schema version mismatch")
    require(runtime.get("schemaVersion") == 1, "Runtime schema version mismatch")
    require(isinstance(entries, list) and len(entries) == generator.TARGET_BRANDS, "Master must contain 600 brands")
    require(isinstance(runtime_entries, list) and len(runtime_entries) == len(entries), "Runtime/master brand count mismatch")
    require(master.get("sourceSnapshot") == evidence, "Pinned source evidence mismatch")
    require(
        master.get("normalizationSourceSnapshot") == normalization_source,
        "Pinned unorm_dart source evidence mismatch",
    )
    require(
        runtime.get("normalizationPolicy") == generator.NORMALIZATION_POLICY,
        "Normalization policy must pin runtime Unicode 17 and corpus parity",
    )
    require("http://" not in json.dumps(runtime) and "https://" not in json.dumps(runtime), "Runtime catalog must not contain URLs")

    ids = [entry.get("brandId") for entry in entries]
    require(len(set(ids)) == len(ids), "Duplicate master brand IDs")
    require(ids == sorted(ids), "Master brand IDs must be deterministically sorted")
    seed_ids = {row["brand_id"] for row in seeds}
    selected_seed_ids = {
        entry["brandId"] for entry in entries
        if entry.get("selectionOrigin") == "user_v5_seed"
    }
    require(seed_ids == selected_seed_ids, "The 183 stable seed IDs were not preserved")

    expected_parity = generator.normalization_parity_payload(entries)
    require(
        master.get("normalizationParity") == expected_parity,
        "Master normalization parity corpus is incomplete or stale",
    )
    master_sha256 = generator.sha256(generator.MASTER_PATH)
    require(parity_result.get("schemaVersion") == 1, "Parity result schema mismatch")
    require(parity_result.get("status") == "passed", "Runtime/build parity did not pass")
    require(
        parity_result.get("normalizationPolicy") == generator.NORMALIZATION_POLICY,
        "Parity result policy mismatch",
    )
    require(
        parity_result.get("sourceMasterFile") == generator.MASTER_PATH.name
        and parity_result.get("sourceMasterSha256") == master_sha256,
        "Parity result is not bound to the current master manifest",
    )
    require(
        parity_result.get("parityCasesSha256") == expected_parity["casesSha256"]
        and parity_result.get("caseCount") == expected_parity["caseCount"]
        and parity_result.get("matchedCaseCount") == expected_parity["caseCount"]
        and parity_result.get("mismatchCount") == 0
        and parity_result.get("mismatches") == [],
        "Parity result count/hash mismatch",
    )
    require(
        parity_result.get("runtimeNormalizer")
        == {"package": "unorm_dart", "version": "0.3.2", "unicodeVersion": "17.0"},
        "Parity runtime normalizer identity mismatch",
    )
    require(
        parity_result.get("buildNormalizer")
        == {
            "engine": expected_parity["buildEngine"],
            "unicodeVersion": expected_parity["pythonUnidataVersion"],
        },
        "Parity build normalizer identity mismatch",
    )

    runtime_by_id = {entry.get("brandId"): entry for entry in runtime_entries}
    require(set(runtime_by_id) == set(ids), "Runtime/master ID set mismatch")
    alias_occurrences: dict[str, list[tuple[dict, str]]] = defaultdict(list)
    total_aliases = 0
    simple_count = 0
    monogram_count = 0
    full_color_count = 0
    total_asset_bytes = 0
    visible_pixels = 0
    expected_assets: set[Path] = set()

    for entry in entries:
        brand_id = entry["brandId"]
        runtime_entry = runtime_by_id[brand_id]
        require(set(runtime_entry) == RUNTIME_FIELDS, f"Unexpected runtime fields: {brand_id}")
        require(runtime_entry == generator.runtime_entry(entry), f"Runtime entry drift: {brand_id}")
        require(entry.get("fullColor") is False, f"Full-color asset is forbidden: {brand_id}")
        full_color_count += int(bool(entry.get("fullColor")))
        require(0.8 <= float(entry.get("opticalScale", 0)) <= 1.15, f"Optical scale out of range: {brand_id}")
        require(entry.get("assetFormat") == "png", f"Non-PNG asset declared: {brand_id}")
        require(entry.get("trademarkAuthorization") == "not_granted", f"Trademark status missing: {brand_id}")
        require(entry.get("trademarkUsage") == "identification_only", f"Trademark usage missing: {brand_id}")
        require(entry.get("trademarkNotes"), f"Trademark notes missing: {brand_id}")
        require(entry.get("isOfficialLogoClaimed") is False, f"Official-logo claim forbidden: {brand_id}")
        require(entry.get("licenseStatus") == "verified", f"License status missing: {brand_id}")
        require(entry.get("licenseSpdx"), f"License identifier missing: {brand_id}")
        require(entry.get("sourceName") and entry.get("sourceReference"), f"Source evidence missing: {brand_id}")
        require(entry.get("categories", [None])[0] in generator.CATEGORY_TARGETS, f"Unknown category: {brand_id}")

        aliases = entry.get("aliases")
        records = entry.get("aliasRecords")
        require(isinstance(aliases, list) and aliases, f"Aliases missing: {brand_id}")
        require(isinstance(records, list) and len(records) == len(aliases), f"Alias provenance mismatch: {brand_id}")
        require([record.get("value") for record in records] == aliases, f"Alias record order mismatch: {brand_id}")
        require(all(record.get("sourceType") and record.get("sourceReference") for record in records), f"Alias source evidence missing: {brand_id}")
        total_aliases += len(aliases)
        for raw_alias in [entry["canonicalName"], *aliases]:
            key = generator.normalize(raw_alias)
            if key:
                alias_occurrences[key].append((entry, raw_alias))

        render_mode = entry.get("renderMode")
        if render_mode == "mono_brand":
            simple_count += 1
            require(entry.get("sourceName") == "Simple Icons", f"Simple Icons source name mismatch: {brand_id}")
            require(entry.get("sourceVersion") == "16.28.0", f"Simple Icons version mismatch: {brand_id}")
            require(entry.get("licenseSpdx") == "CC0-1.0", f"Simple Icons package license mismatch: {brand_id}")
            svg_path = generator.PROJECT_ROOT / entry.get("originalSvgPath", "")
            require(svg_path.is_file(), f"Original Simple Icons SVG missing: {brand_id}")
            require(generator.sha256(svg_path) == entry.get("originalSvgSha256"), f"Original SVG hash mismatch: {brand_id}")
            require(entry.get("monogramText") is None, f"Simple Icons entry contains monogram text: {brand_id}")
        elif render_mode == "monogram":
            monogram_count += 1
            require(entry.get("sourceName") == "Cardock generated monogram", f"Monogram source mismatch: {brand_id}")
            require(entry.get("licenseSpdx") == "LicenseRef-Cardock-Generated", f"Monogram license mismatch: {brand_id}")
            require(entry.get("monogramText"), f"Monogram text missing: {brand_id}")
            require(entry.get("originalSvgPath") is None and entry.get("originalSvgSha256") is None, f"Monogram must not claim an upstream SVG: {brand_id}")
        else:
            raise ValueError(f"Unknown render mode: {brand_id}")

        if entry.get("selectionOrigin") == "simple_icons_relevance_extension":
            require(int(entry.get("selectionScore", 0)) >= 7, f"Low-signal extension: {brand_id}")
            reason = str(entry.get("selectionReason", ""))
            require("curated_high_signal_service" in reason or "category_terms:" in reason, f"Extension lacks a relevance signal: {brand_id}")

        asset = generator.APP_DIR / entry["assetPath"]
        asset = asset.resolve()
        expected_root = generator.ICON_ROOT.resolve()
        require(expected_root in asset.parents, f"Asset path escapes icon root: {brand_id}")
        require(asset.is_file(), f"Asset missing: {brand_id}")
        require(asset.name == f"{brand_id}.png", f"Asset filename mismatch: {brand_id}")
        require(generator.sha256(asset) == entry.get("assetSha256"), f"Asset hash mismatch: {brand_id}")
        require(asset.stat().st_size == entry.get("assetBytes"), f"Asset byte count mismatch: {brand_id}")
        png = audit_png(asset)
        visible_pixels += png["visiblePixelCount"]
        total_asset_bytes += asset.stat().st_size
        expected_assets.add(asset)

    require(total_aliases >= generator.MINIMUM_ALIASES, "Raw sourced alias target not met")
    require(full_color_count == 0, "Full-color asset count must be zero")
    require(simple_count + monogram_count == generator.TARGET_BRANDS, "Render-mode count mismatch")

    risky = {generator.normalize(value) for value in generator.NEVER_AUTO_ALIASES}
    collision_count = 0
    for key, occurrences in alias_occurrences.items():
        involved_ids = {entry["brandId"] for entry, _ in occurrences}
        is_ambiguous = len(involved_ids) > 1 or key in risky
        if len(involved_ids) > 1:
            collision_count += 1
        if is_ambiguous:
            for entry, raw_alias in occurrences:
                require(raw_alias in entry["ambiguousAliases"], f"Unmarked ambiguous alias {raw_alias!r} in {entry['brandId']}")

    actual_assets = {path.resolve() for path in generator.ICON_ROOT.glob("*.png")}
    require(actual_assets == expected_assets, "Extra or missing PNG assets detected")
    require(not any(generator.ASSET_ROOT.rglob("*.svg")), "Raw SVG must remain outside APK assets")
    notice = generator.NOTICE_PATH.read_text(encoding="utf-8")
    require(
        "unorm_dart 0.3.2" in notice
        and "MIT License" in notice
        and "Copyright (c) 2018 Yasuhiro Shimizu" in notice,
        "Bundled third-party notice is missing the normalization dependency",
    )
    bundled_files = [path for path in generator.ASSET_ROOT.rglob("*") if path.is_file()]
    bundled_bytes = sum(path.stat().st_size for path in bundled_files)
    require(bundled_bytes <= MAX_BUNDLED_BYTES, "Brand asset increment exceeds 5 MiB")
    require(validation.get("masterManifestSha256") == master_sha256, "Validation/master hash mismatch")
    require(validation.get("normalizationPolicy") == generator.NORMALIZATION_POLICY, "Validation normalization policy mismatch")
    require(
        validation.get("normalizationSourceManifestSha256")
        == normalization_source["sourceManifestSha256"],
        "Validation unorm_dart source hash mismatch",
    )
    require(
        validation.get("pubspecLockSha256") == normalization_source["pubspecLockSha256"],
        "Validation pubspec.lock hash mismatch",
    )
    require(master.get("metrics", {}).get("rawAliasCount") == total_aliases, "Recorded alias metric mismatch")
    require(master.get("metrics", {}).get("assetBytes") == total_asset_bytes, "Recorded asset metric mismatch")

    return {
        "brandCount": len(entries),
        "rawSourcedAliasCount": total_aliases,
        "simpleIconsAssetCount": simple_count,
        "monogramAssetCount": monogram_count,
        "fullColorCount": full_color_count,
        "normalizedCollisionCount": collision_count,
        "assetCount": len(expected_assets),
        "assetBytes": total_asset_bytes,
        "bundledBrandBytes": bundled_bytes,
        "visiblePixelCount": visible_pixels,
        "normalizationParityCaseCount": expected_parity["caseCount"],
        "normalizationParityManifestSha256": generator.sha256(
            generator.NORMALIZATION_PARITY_PATH
        ),
        "normalizationSourceManifestSha256": normalization_source[
            "sourceManifestSha256"
        ],
        "pubspecLockSha256": normalization_source["pubspecLockSha256"],
        "runtimeCatalogSha256": generator.sha256(generator.RUNTIME_PATH),
        "masterManifestSha256": master_sha256,
    }


def main() -> None:
    try:
        metrics = audit()
        validation = read_json(generator.VALIDATION_PATH)
        validation.update(
            {
                "status": "passed",
                "normalizationParityStatus": "passed",
                "normalizationParityManifestSha256": metrics[
                    "normalizationParityManifestSha256"
                ],
                "audit": metrics,
                "checks": [
                    "source_lock", "stable_seed_ids", "schema", "alias_provenance",
                    "ambiguity_policy", "license", "trademark", "asset_hash",
                    "png_dimensions", "transparent_background", "monochrome_pixels",
                    "optical_scale", "no_svg_in_apk", "bundle_size",
                    "unorm_dart_source_lock", "normalization_runtime_build_parity",
                ],
            }
        )
        generator.write_json(generator.VALIDATION_PATH, validation)
        print(json.dumps(metrics, ensure_ascii=False, sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, zlib.error) as error:
        print(f"AUDIT_FAIL {type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
