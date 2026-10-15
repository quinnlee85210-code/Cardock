#!/usr/bin/env python3
"""Generate Cardock's deterministic offline brand catalog.

The tool reads the user-provided V5 seed and the pinned Simple Icons snapshot.
It never downloads data. ``prepare`` creates a reviewed, deterministic 600-item
selection and one local HTML sprite. ``finalize`` records generated PNG hashes
and writes the runtime catalog plus the full source/trademark audit manifest.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path
from urllib.parse import urlparse


SCRIPT_DIR = Path(__file__).resolve().parent
APP_DIR = SCRIPT_DIR.parents[1]
PROJECT_ROOT = SCRIPT_DIR.parents[2]
HANDOFF_ROOT = PROJECT_ROOT / "_handoff"
SIMPLE_ROOT = HANDOFF_ROOT / "external_sources" / "simple-icons-16.28.0"
SIMPLE_TGZ = HANDOFF_ROOT / "external_sources" / "simple-icons-16.28.0.tgz"
UNORM_ROOT = HANDOFF_ROOT / "external_sources" / "unorm_dart-0.3.2"
UNORM_ARCHIVE = HANDOFF_ROOT / "external_sources" / "unorm_dart-0.3.2.tar.gz"
SEED_PATH = (
    HANDOFF_ROOT
    / "Cardock_UI_Quality_Upgrade_Handoff_V5.0"
    / "brand_catalog"
    / "core_seed_from_user_research.csv"
)
LOCK_PATH = SCRIPT_DIR / "simple_icons_source_lock.json"
GENERATED_DIR = SCRIPT_DIR / ".generated"
PLAN_PATH = GENERATED_DIR / "selection_plan.json"
SPRITE_PATH = GENERATED_DIR / "brand_sprite.html"
LAYOUT_PATH = GENERATED_DIR / "brand_sprite_layout.json"
ASSET_ROOT = APP_DIR / "assets" / "brands" / "v1"
ICON_ROOT = ASSET_ROOT / "icons"
RUNTIME_PATH = ASSET_ROOT / "runtime_catalog.json"
NOTICE_PATH = ASSET_ROOT / "THIRD_PARTY_NOTICES.txt"
MASTER_PATH = PROJECT_ROOT / "manifests" / "cardock-brand-catalog-v1-source.json"
NORMALIZATION_SOURCE_PATH = PROJECT_ROOT / "manifests" / "cardock-unorm-dart-source.json"
NORMALIZATION_PARITY_PATH = (
    PROJECT_ROOT / "manifests" / "cardock-brand-catalog-v1-normalization-parity.json"
)
VALIDATION_PATH = (
    PROJECT_ROOT / "manifests" / "cardock-brand-catalog-v1-generation.json"
)
PUBSPEC_PATH = APP_DIR / "pubspec.yaml"
PUBSPEC_LOCK_PATH = APP_DIR / "pubspec.lock"

NORMALIZATION_POLICY = (
    "unicode_nfkc_v1_runtime_unorm_dart_0.3.2_"
    "unicode17_build_corpus_parity_v1"
)

TARGET_BRANDS = 600
MINIMUM_ALIASES = 1500
SPRITE_CELL = 96
SPRITE_COLUMNS = 20

CATEGORY_TARGETS = {
    "crypto_payment": 80,
    "telecom": 100,
    "cloud_vps_domain": 100,
    "email_privacy_identity": 50,
    "insurance_finance": 70,
    "social_media_entertainment": 70,
    "ecommerce_payment_travel": 60,
    "productivity_ai_dev": 70,
}

SEED_CATEGORY_MAP = {
    "crypto_u_card": "crypto_payment",
    "crypto_exchange": "crypto_payment",
    "crypto_payment": "crypto_payment",
    "crypto_wallet": "crypto_payment",
    "payment": "ecommerce_payment_travel",
    "telecom": "telecom",
    "cloud_vps_domain": "cloud_vps_domain",
    "email_privacy": "email_privacy_identity",
    "insurance": "insurance_finance",
    "social_entertainment": "social_media_entertainment",
    "ecommerce_payment": "ecommerce_payment_travel",
    "productivity_ai_dev": "productivity_ai_dev",
}

# Explicit high-signal services receive priority. Keyword scoring fills remaining
# category gaps; it never selects alphabetically merely to reach a count.
CURATED_SLUGS = {
    "crypto_payment": {
        "bitcoin", "ethereum", "tether", "solana", "cardano", "dogecoin",
        "litecoin", "monero", "zcash", "xrp", "stellar", "polkadot",
        "avalanche", "polygon", "arbitrum", "optimism", "near", "tron",
        "binance", "coinbase", "kraken", "okx", "bybit", "bitget",
        "uniswap", "aave", "chainlink", "metamask", "ledger", "trustpilot",
        "blockchaindotcom", "cryptocom", "nexo", "bitpay", "web3dotjs",
    },
    "telecom": {
        "vodafone", "verizon", "tmobile", "orange", "telefonica", "telstra",
        "airtel", "jio", "xfinity", "spectrum", "rogers", "bell", "telus",
        "singtel", "starhub", "softbank", "docomo", "kddi", "sktelecom",
        "chinaunicom", "chinatelecom", "huawei", "zte", "samsung",
    },
    "cloud_vps_domain": {
        "amazonwebservices", "googlecloud", "microsoftazure", "cloudflare",
        "digitalocean", "linode", "vultr", "hetzner", "ovh", "akamai",
        "fastly", "vercel", "netlify", "heroku", "render", "railway",
        "flydotio", "firebase", "supabase", "oracle", "ibmcloud",
        "alibabacloud", "tencentcloud", "huawei", "godaddy", "namecheap",
        "hostinger", "siteground", "wpengine", "cloudways", "openstack",
        "bunnydotnet", "backblaze", "cloudinary", "cloudsmith", "cloudbees",
        "databricks", "deno", "elasticcloud", "mongodb", "neon", "planetscale",
        "redis", "scaleway", "snowflake", "wasabi", "infomaniak", "ionos",
        "upcloud", "contabo",
    },
    "email_privacy_identity": {
        "gmail", "protonmail", "outlook", "icloud", "fastmail", "maildotru",
        "tutanota", "signal", "telegram", "wire", "simplelogin", "addydotio",
        "1password", "bitwarden", "lastpass", "dashlane", "auth0", "okta",
        "protonvpn", "nordvpn", "expressvpn", "surfshark", "mullvad",
        "cloudflare", "duckduckgo", "torproject", "adguard", "yubico",
        "brave", "firefoxbrowser", "googlechrome", "opera", "vivaldi",
        "haveibeenpwned", "keepassxc", "keeper", "threema", "ublockorigin",
        "tails", "proton", "protoncalendar", "protondrive",
    },
    "insurance_finance": {
        "allianz", "aig", "axa", "metlife", "prudential", "paypal", "wise",
        "revolut", "stripe", "klarna", "afterpay", "americanexpress", "visa",
        "mastercard", "wellsfargo", "bankofamerica", "hsbc", "barclays",
        "monzo", "starlingbank", "cashapp", "zelle", "westernunion", "xero",
        "aib", "bunq", "n26", "chase", "deutschebank", "robinhood",
        "tradingview", "webmoney", "youhodler", "zerodha", "xendit", "paytm",
    },
    "social_media_entertainment": {
        "youtube", "youtubemusic", "netflix", "spotify", "applemusic",
        "amazonprime", "primevideo", "disneyplus", "hulu", "max", "twitch",
        "tiktok", "instagram", "facebook", "x", "reddit", "discord",
        "snapchat", "pinterest", "linkedin", "wechat", "sinaweibo", "zhihu",
        "xiaohongshu", "bilibili", "douban", "line", "kakaotalk", "medium",
        "applepodcasts", "audible", "bandcamp", "behance", "bluesky",
        "crunchyroll", "deezer", "deviantart", "dribbble", "flickr",
        "goodreads", "imdb", "mastodon", "messenger", "mixcloud",
        "myanimelist", "patreon", "plex", "pocketcasts", "qq", "quora",
        "rumble", "soundcloud", "steam", "strava", "substack", "threads",
        "tumblr", "vimeo", "vk", "whatsapp", "webtoon", "lastdotfm",
        "meetup", "odysee", "peertube",
    },
    "ecommerce_payment_travel": {
        "amazon", "ebay", "etsy", "alibabadotcom", "aliexpress", "shopify",
        "walmart", "target", "bestbuy", "ikea", "zalando", "zara", "wish",
        "paypal", "alipay", "wechat", "stripe", "adyen", "square", "klarna",
        "airbnb", "bookingdotcom", "expedia", "tripdotcom", "uber", "lyft",
        "doordash", "ubereats", "grab", "deliveroo", "justeat", "zomato",
        "applepay", "carrefour", "groupon", "instacart", "nike", "rakuten",
        "shopee", "shopware", "starbucks", "swiggy", "tesco", "ticketmaster",
        "tripadvisor", "vinted", "payoneer", "lemonsqueezy",
    },
    "productivity_ai_dev": {
        "openai", "anthropic", "googlegemini", "perplexity", "huggingface",
        "github", "gitlab", "bitbucket", "docker", "npm", "pypi", "sentry",
        "posthog", "figma", "canva", "notion", "slack", "microsoftteams",
        "zoom", "trello", "asana", "jira", "confluence", "linear", "airtable",
        "dropbox", "googledrive", "googledocs", "googlesheets", "grammarly",
        "zapier", "ifttt", "make", "replit", "vercel", "supabase", "neon",
        "algolia", "atlassian", "basecamp", "box", "calendly", "clickup",
        "coda", "codeberg", "codecademy", "codesandbox", "coursera", "datadog",
        "datacamp", "deepnote", "evernote", "gitbook", "googlecalendar",
        "googlemeet", "googlephotos", "hubspot", "intercom", "jetbrains",
        "kaggle", "loom", "mailchimp", "miro", "n8n", "pagerduty", "penpot",
        "postman", "raycast", "skillshare", "squarespace", "stackoverflow",
        "todoist", "typeform", "webflow", "wix", "wordpress", "zendesk",
        "zoho", "zotero", "dropbox", "deepseek", "claude",
    },
}

CATEGORY_KEYWORDS = {
    "crypto_payment": {
        "bitcoin", "crypto", "coin", "blockchain", "wallet", "ethereum",
        "chain", "defi", "token", "solana", "cardano", "exchange",
    },
    "telecom": {
        "telecom", "telekom", "mobile", "wireless", "cellular", "broadband",
        "fiber", "fibre", "telco", "phone", "communications",
    },
    "cloud_vps_domain": {
        "cloud", "hosting", "host", "domain", "server", "cdn", "deploy",
        "infrastructure", "compute", "database", "storage", "platform",
    },
    "email_privacy_identity": {
        "mail", "email", "privacy", "vpn", "security", "identity", "auth",
        "password", "anonymous", "encrypt", "firewall", "antivirus",
    },
    "insurance_finance": {
        "insurance", "assurance", "bank", "finance", "financial", "invest",
        "broker", "credit", "pension", "wealth", "mutual", "capital",
    },
    "social_media_entertainment": {
        "social", "music", "video", "stream", "gaming", "games", "media",
        "chat", "community", "podcast", "radio", "tv", "movie", "anime",
    },
    "ecommerce_payment_travel": {
        "pay", "payment", "shop", "store", "commerce", "market", "travel",
        "hotel", "flight", "airlines", "food", "delivery", "ride", "ticket",
    },
    "productivity_ai_dev": {
        "ai", "productivity", "collaboration", "project", "design", "developer",
        "code", "dev", "analytics", "monitoring", "automation", "workspace",
        "database", "api", "notebook", "docs", "office", "crm", "support",
    },
}

EXCLUDED_WORDS = {
    "language", "framework", "compiler", "syntax", "format", "protocol",
    "library", "runtime", "kernel", "distribution", "desktop environment",
    "window manager", "package manager", "font", "codec", "markup",
}

GENERIC_SOURCE_HOSTS = {
    "github.com", "raw.githubusercontent.com", "gitlab.com", "figma.com",
    "www.figma.com", "commons.wikimedia.org", "wikipedia.org", "en.wikipedia.org",
    "cdn.jsdelivr.net", "simpleicons.org", "www.simpleicons.org",
}

NEVER_AUTO_ALIASES = {
    "x", "max", "line", "three", "bell", "m1", "tm", "one", "prime",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def sha256_json(value: object) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest().upper()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )


def normalize(value: str) -> str:
    # Mirrors the runtime order: Unicode NFKC, lowercase, then the project's
    # agreed separator folding. Runtime Unicode 17.0 is provided by the locked
    # unorm_dart 0.3.2 dependency. Python records its own Unicode data version,
    # and the Dart parity tool must approve every emitted raw catalog value.
    value = unicodedata.normalize("NFKC", value).lower()
    ignored = {
        "!", '"', "#", "$", "%", "&", "'", "(", ")", "*", "+", ",",
        "-", ".", "/", ":", ";", "<", "=", ">", "?", "@", "[", "\\",
        "]", "^", "_", "`", "{", "|", "}", "~", "\u00b7", "\u2022",
        "\u2010", "\u2011", "\u2012", "\u2013", "\u2014", "\u2015",
        "\u2026", "\u2212", "\u3001", "\u3002", "\ufe58", "\ufe63",
        "\uff0c", "\uff1a", "\uff1b",
    }
    whitespace = {
        "\u0009", "\u000a", "\u000b", "\u000c", "\u000d", "\u0020",
        "\u0085", "\u00a0", "\u1680", "\u2000", "\u2001", "\u2002",
        "\u2003", "\u2004", "\u2005", "\u2006", "\u2007", "\u2008",
        "\u2009", "\u200a", "\u2028", "\u2029", "\u202f", "\u205f",
        "\u3000",
    }
    return "".join(char for char in value if char not in ignored and char not in whitespace)


def load_and_verify_unorm_source() -> dict:
    manifest = json.loads(NORMALIZATION_SOURCE_PATH.read_text(encoding="utf-8"))
    required_identity = {
        "schemaVersion": 1,
        "package": "unorm_dart",
        "version": "0.3.2",
        "licenseSpdx": "MIT",
        "unicodeVersion": "17.0",
        "runtimeNetwork": False,
    }
    for key, expected in required_identity.items():
        if manifest.get(key) != expected:
            raise SystemExit(f"unorm_dart source manifest mismatch: {key}")

    local_files = {
        "archiveSha256": UNORM_ARCHIVE,
        "licenseSha256": UNORM_ROOT / "LICENSE",
        "pubspecSha256": UNORM_ROOT / "pubspec.yaml",
        "unicodeDataSha256": UNORM_ROOT / "lib" / "src" / "unormdata.dart",
    }
    for field, path in local_files.items():
        if not path.is_file() or sha256(path) != str(manifest.get(field, "")).upper():
            raise SystemExit(f"unorm_dart local source evidence mismatch: {field}")
    if UNORM_ARCHIVE.stat().st_size != manifest.get("archiveBytes"):
        raise SystemExit("unorm_dart archive byte count mismatch")

    app_pubspec = PUBSPEC_PATH.read_text(encoding="utf-8")
    if not re.search(r"(?m)^  unorm_dart:\s*0\.3\.2\s*$", app_pubspec):
        raise SystemExit("pubspec.yaml must exactly pin unorm_dart 0.3.2")
    lock_text = PUBSPEC_LOCK_PATH.read_text(encoding="utf-8")
    lock_lines = lock_text.splitlines()
    try:
        start = lock_lines.index("  unorm_dart:")
    except ValueError as error:
        raise SystemExit("pubspec.lock is missing unorm_dart") from error
    end = len(lock_lines)
    for index in range(start + 1, len(lock_lines)):
        line = lock_lines[index]
        if line.startswith("  ") and not line.startswith("    "):
            end = index
            break
    lock_block = "\n".join(lock_lines[start:end])
    expected_archive_hash = str(manifest["archiveSha256"]).lower()
    required_lock_patterns = (
        r'(?m)^    dependency: "direct main"$',
        r"(?m)^      name: unorm_dart$",
        rf'(?m)^      sha256: "{re.escape(expected_archive_hash)}"$',
        r'(?m)^    source: hosted$',
        r'(?m)^    version: "0\.3\.2"$',
    )
    if any(re.search(pattern, lock_block) is None for pattern in required_lock_patterns):
        raise SystemExit("pubspec.lock unorm_dart identity/hash mismatch")

    return {
        "package": "unorm_dart",
        "version": "0.3.2",
        "unicodeVersion": "17.0",
        "licenseSpdx": "MIT",
        "runtimeNetwork": False,
        "sourceManifestPath": str(
            NORMALIZATION_SOURCE_PATH.relative_to(PROJECT_ROOT)
        ).replace("\\", "/"),
        "sourceManifestSha256": sha256(NORMALIZATION_SOURCE_PATH),
        "archivePath": str(UNORM_ARCHIVE.relative_to(PROJECT_ROOT)).replace("\\", "/"),
        "archiveBytes": UNORM_ARCHIVE.stat().st_size,
        "archiveSha256": sha256(UNORM_ARCHIVE),
        "licenseSha256": sha256(UNORM_ROOT / "LICENSE"),
        "pubspecSha256": sha256(UNORM_ROOT / "pubspec.yaml"),
        "unicodeDataSha256": sha256(UNORM_ROOT / "lib" / "src" / "unormdata.dart"),
        "pubspecLockPath": str(PUBSPEC_LOCK_PATH.relative_to(PROJECT_ROOT)).replace("\\", "/"),
        "pubspecLockSha256": sha256(PUBSPEC_LOCK_PATH),
        "pubspecLockPackageSha256": expected_archive_hash.upper(),
    }


def flatten_alias_values(value: object) -> list[str]:
    result: list[str] = []
    if isinstance(value, str):
        result.append(value)
    elif isinstance(value, list):
        for item in value:
            result.extend(flatten_alias_values(item))
    elif isinstance(value, dict):
        if isinstance(value.get("title"), str):
            result.append(value["title"])
        else:
            for child in value.values():
                result.extend(flatten_alias_values(child))
    return result


def useful_source_host(url: str | None) -> str | None:
    if not url:
        return None
    try:
        host = (urlparse(url).hostname or "").lower()
    except ValueError:
        return None
    if host.startswith("www."):
        host = host[4:]
    if not host or host in GENERIC_SOURCE_HOSTS or host.endswith("githubusercontent.com"):
        return None
    return host


def load_and_verify_sources() -> tuple[list[dict], list[dict], dict]:
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    checks = {
        "tgzSha256": sha256(SIMPLE_TGZ),
        "packageJsonSha256": sha256(SIMPLE_ROOT / "package.json"),
        "metadataSha256": sha256(SIMPLE_ROOT / "data" / "simple-icons.json"),
        "licenseSha256": sha256(SIMPLE_ROOT / "LICENSE.md"),
        "disclaimerSha256": sha256(SIMPLE_ROOT / "DISCLAIMER.md"),
    }
    mismatches = [key for key, actual in checks.items() if lock.get(key) != actual]
    if mismatches:
        raise SystemExit(f"Pinned Simple Icons evidence mismatch: {mismatches}")
    package = json.loads((SIMPLE_ROOT / "package.json").read_text(encoding="utf-8"))
    if package.get("name") != lock["packageName"] or package.get("version") != lock["version"]:
        raise SystemExit("Simple Icons package identity mismatch")
    metadata = json.loads(
        (SIMPLE_ROOT / "data" / "simple-icons.json").read_text(encoding="utf-8")
    )
    with SEED_PATH.open(encoding="utf-8-sig", newline="") as handle:
        seeds = list(csv.DictReader(handle))
    if len(seeds) != 183 or len({row["brand_id"] for row in seeds}) != 183:
        raise SystemExit("V5 seed identity/count changed")
    return seeds, metadata, {**lock, **checks, "iconCount": len(metadata)}


def metadata_aliases(item: dict) -> list[dict]:
    records = [
        {"value": item["title"], "sourceType": "simple_icons_title", "sourceReference": item["source"]},
        {"value": item["slug"], "sourceType": "simple_icons_slug", "sourceReference": item["source"]},
    ]
    for value in flatten_alias_values(item.get("aliases", {})):
        records.append(
            {"value": value, "sourceType": "simple_icons_metadata_alias", "sourceReference": item["source"]}
        )
    for candidate in (item.get("source"), item.get("guidelines")):
        host = useful_source_host(candidate)
        if host:
            records.append(
                {"value": host, "sourceType": "simple_icons_source_host", "sourceReference": candidate}
            )
    return dedupe_alias_records(records)


def dedupe_alias_records(records: list[dict]) -> list[dict]:
    result: list[dict] = []
    seen: set[str] = set()
    for record in records:
        value = str(record.get("value", "")).strip()
        if not value or value in seen:
            continue
        seen.add(value)
        result.append({**record, "value": value})
    return result


def metadata_index(metadata: list[dict]) -> tuple[dict[str, dict], dict[str, set[str]]]:
    by_slug = {item["slug"]: item for item in metadata}
    keys: dict[str, set[str]] = defaultdict(set)
    for item in metadata:
        for record in metadata_aliases(item):
            key = normalize(record["value"])
            if key:
                keys[key].add(item["slug"])
    return by_slug, keys


def match_seed(seed: dict, alias_index: dict[str, set[str]]) -> tuple[str | None, str]:
    candidates: set[str] = set()
    for raw in [seed["brand_id"], seed["canonical_name"], *seed["aliases"].split(";")]:
        key = normalize(raw)
        if len(alias_index.get(key, set())) == 1:
            candidates.update(alias_index[key])
    if len(candidates) == 1:
        return next(iter(candidates)), "unique_exact_seed_identity"
    return None, "no_unique_exact_simple_icons_match"


def candidate_category(item: dict) -> tuple[str | None, int, list[str]]:
    title = item["title"].lower()
    slug = item["slug"].lower()
    words = set(re.findall(r"[a-z0-9]+", title))
    phrase = title.replace("-", " ")
    if any(excluded in phrase for excluded in EXCLUDED_WORDS):
        return None, 0, ["excluded_non_account_technology"]
    best: tuple[str | None, int, list[str]] = (None, 0, [])
    for category, keywords in CATEGORY_KEYWORDS.items():
        reasons: list[str] = []
        score = 0
        has_category_signal = False
        if slug in CURATED_SLUGS[category]:
            score += 100
            reasons.append("curated_high_signal_service")
            has_category_signal = True
        matched = sorted(
            keyword for keyword in keywords
            if keyword in words or (len(keyword) >= 5 and keyword in slug)
        )
        if matched:
            score += min(20, 5 * len(matched))
            reasons.append("category_terms:" + ",".join(matched[:4]))
            has_category_signal = True
        if not has_category_signal:
            continue
        if item.get("guidelines"):
            score += 2
            reasons.append("brand_guidelines_present")
        if useful_source_host(item.get("source")):
            score += 2
            reasons.append("direct_source_host")
        if flatten_alias_values(item.get("aliases", {})):
            score += 1
            reasons.append("upstream_aliases_present")
        if score > best[1]:
            best = (category, score, reasons)
    return best


def make_monogram(value: str) -> str:
    words = [part for part in re.split(r"[^0-9A-Za-z]+", value) if part]
    if len(words) >= 2:
        return (words[0][0] + words[1][0]).upper()
    ascii_chars = [char for char in value if char.isascii() and char.isalnum()]
    if ascii_chars:
        return "".join(ascii_chars[:2]).upper()
    return "".join(list(value.strip())[:2]) or "?"


def build_selection(seeds: list[dict], metadata: list[dict], evidence: dict) -> dict:
    by_slug, alias_index = metadata_index(metadata)
    entries: list[dict] = []
    used_slugs: set[str] = set()
    used_ids: set[str] = set()

    for seed in seeds:
        brand_id = seed["brand_id"]
        if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", brand_id):
            raise SystemExit(f"Invalid seed brand ID: {brand_id}")
        category = SEED_CATEGORY_MAP[seed["category"]]
        slug, reason = match_seed(seed, alias_index)
        simple = by_slug.get(slug) if slug else None
        if simple:
            used_slugs.add(simple["slug"])
        aliases = [
            {
                "value": seed["canonical_name"],
                "sourceType": "user_v5_seed_canonical",
                "sourceReference": "core_seed_from_user_research.csv",
            },
            *(
                {
                    "value": value.strip(),
                    "sourceType": "user_v5_seed_alias",
                    "sourceReference": "core_seed_from_user_research.csv",
                }
                for value in seed["aliases"].split(";")
                if value.strip()
            ),
        ]
        if simple:
            aliases.extend(metadata_aliases(simple))
        entries.append(
            build_entry(
                brand_id=brand_id,
                canonical_name=seed["canonical_name"],
                aliases=dedupe_alias_records(aliases),
                category=category,
                regions=[value for value in seed["regions"].split(";") if value],
                simple=simple,
                selection_origin="user_v5_seed",
                selection_reason=reason,
                selection_score=1000,
            )
        )
        used_ids.add(brand_id)

    counts = Counter(entry["categories"][0] for entry in entries)
    candidates: dict[str, list[tuple[int, str, dict, list[str]]]] = defaultdict(list)
    for item in metadata:
        if item["slug"] in used_slugs:
            continue
        icon = SIMPLE_ROOT / "icons" / f"{item['slug']}.svg"
        if not icon.is_file() or not item.get("source"):
            continue
        category, score, reasons = candidate_category(item)
        if category is None or score < 7:
            continue
        candidates[category].append((-score, item["title"].casefold(), item, reasons))
    for values in candidates.values():
        values.sort(key=lambda value: (value[0], value[1], value[2]["slug"]))

    for category, target in CATEGORY_TARGETS.items():
        needed = max(0, target - counts[category])
        for negative_score, _, item, reasons in candidates[category]:
            if needed <= 0:
                break
            if item["slug"] in used_slugs:
                continue
            brand_id = unique_extension_id(item["slug"], used_ids)
            entries.append(
                build_entry(
                    brand_id=brand_id,
                    canonical_name=item["title"],
                    aliases=metadata_aliases(item),
                    category=category,
                    regions=["global"],
                    simple=item,
                    selection_origin="simple_icons_relevance_extension",
                    selection_reason=";".join(reasons),
                    selection_score=-negative_score,
                )
            )
            used_ids.add(brand_id)
            used_slugs.add(item["slug"])
            counts[category] += 1
            needed -= 1

    if len(entries) < TARGET_BRANDS:
        remaining: list[tuple[int, str, str, dict, list[str]]] = []
        for category, values in candidates.items():
            for negative_score, title, item, reasons in values:
                if item["slug"] not in used_slugs:
                    remaining.append((negative_score, title, category, item, reasons))
        remaining.sort(key=lambda value: (value[0], value[1], value[3]["slug"]))
        for negative_score, _, category, item, reasons in remaining:
            if len(entries) >= TARGET_BRANDS:
                break
            brand_id = unique_extension_id(item["slug"], used_ids)
            entries.append(
                build_entry(
                    brand_id=brand_id,
                    canonical_name=item["title"],
                    aliases=metadata_aliases(item),
                    category=category,
                    regions=["global"],
                    simple=item,
                    selection_origin="simple_icons_relevance_extension",
                    selection_reason="quota_rebalance;" + ";".join(reasons),
                    selection_score=-negative_score,
                )
            )
            used_ids.add(brand_id)
            used_slugs.add(item["slug"])
            counts[category] += 1

    if len(entries) != TARGET_BRANDS:
        raise SystemExit(f"Quality-filtered catalog has {len(entries)}, expected {TARGET_BRANDS}")

    mark_ambiguities(entries)
    return {
        "schemaVersion": 1,
        "generator": "app/tool/brand_catalog/generate_brand_catalog.py",
        "sourceSnapshot": evidence,
        "brands": sorted(entries, key=lambda entry: entry["brandId"]),
    }


def unique_extension_id(slug: str, used_ids: set[str]) -> str:
    candidate = f"si.{slug}"
    suffix = 2
    while candidate in used_ids:
        candidate = f"si.{slug}.{suffix}"
        suffix += 1
    return candidate


def build_entry(
    *,
    brand_id: str,
    canonical_name: str,
    aliases: list[dict],
    category: str,
    regions: list[str],
    simple: dict | None,
    selection_origin: str,
    selection_reason: str,
    selection_score: int,
) -> dict:
    render_mode = "mono_brand" if simple else "monogram"
    color = f"#{simple['hex'].upper()}" if simple else generated_color(brand_id)
    source_name = "Simple Icons" if simple else "Cardock generated monogram"
    source_reference = (
        simple["source"] if simple else "app/tool/brand_catalog/generate_brand_catalog.py"
    )
    upstream_license = simple.get("license", {}).get("type") if simple else None
    return {
        "brandId": brand_id,
        "canonicalName": canonical_name,
        "aliasRecords": aliases,
        "aliases": [record["value"] for record in aliases],
        "ambiguousAliases": [],
        "categories": [category],
        "regions": regions or ["global"],
        "assetPath": f"assets/brands/v1/icons/{brand_id}.png",
        "assetFormat": "png",
        "renderMode": render_mode,
        "brandColor": color,
        "opticalScale": 1.0,
        "minimumRenderableDp": 24,
        "fullColor": False,
        "monogramText": make_monogram(canonical_name) if not simple else None,
        "sourceName": source_name,
        "sourceVersion": "16.28.0" if simple else "1",
        "sourceKey": simple["slug"] if simple else brand_id,
        "sourceReference": source_reference,
        "guidelinesReference": simple.get("guidelines") if simple else None,
        "licenseStatus": "verified",
        "licenseSpdx": "CC0-1.0" if simple else "LicenseRef-Cardock-Generated",
        "upstreamSourceLicenseSpdx": upstream_license,
        "trademarkAuthorization": "not_granted",
        "trademarkUsage": "identification_only",
        "trademarkNotes": (
            "Simple Icons artwork is used for offline identification only; "
            "no trademark authorization, sponsorship, or endorsement is claimed."
            if simple
            else "Cardock-generated neutral monogram; not an official brand logo. "
            "The referenced name may remain a third-party trademark."
        ),
        "isOfficialLogoClaimed": False,
        "selectionOrigin": selection_origin,
        "selectionReason": selection_reason,
        "selectionScore": selection_score,
        "originalSvgPath": (
            str((SIMPLE_ROOT / "icons" / f"{simple['slug']}.svg").relative_to(PROJECT_ROOT)).replace("\\", "/")
            if simple else None
        ),
        "originalSvgSha256": (
            sha256(SIMPLE_ROOT / "icons" / f"{simple['slug']}.svg") if simple else None
        ),
        "assetSha256": None,
        "assetBytes": None,
    }


def generated_color(brand_id: str) -> str:
    palette = ["3F63D8", "6845D6", "0A8069", "A04B65", "566477", "7A5A14"]
    index = int(hashlib.sha256(brand_id.encode("utf-8")).hexdigest()[:8], 16)
    return "#" + palette[index % len(palette)]


def mark_ambiguities(entries: list[dict]) -> None:
    aliases: dict[str, list[tuple[dict, str]]] = defaultdict(list)
    for entry in entries:
        for value in entry["aliases"]:
            key = normalize(value)
            if key:
                aliases[key].append((entry, value))
    risky = {normalize(value) for value in NEVER_AUTO_ALIASES}
    for key, occurrences in aliases.items():
        ids = {entry["brandId"] for entry, _ in occurrences}
        if len(ids) > 1 or key in risky:
            for entry, raw in occurrences:
                if raw not in entry["ambiguousAliases"]:
                    entry["ambiguousAliases"].append(raw)
    for entry in entries:
        entry["ambiguousAliases"].sort(key=str.casefold)


def normalization_parity_payload(entries: list[dict]) -> dict:
    roles_by_raw: dict[str, set[str]] = defaultdict(set)
    for entry in entries:
        roles_by_raw[entry["canonicalName"]].add("canonicalName")
        for raw in entry["aliases"]:
            roles_by_raw[raw].add("alias")
        for raw in entry["ambiguousAliases"]:
            roles_by_raw[raw].add("ambiguousAlias")
    cases = [
        {
            "raw": raw,
            "buildKey": normalize(raw),
            "roles": sorted(roles),
        }
        for raw, roles in sorted(roles_by_raw.items(), key=lambda item: item[0])
    ]
    return {
        "normalizationPolicy": NORMALIZATION_POLICY,
        "buildEngine": "python_unicodedata",
        "pythonUnidataVersion": unicodedata.unidata_version,
        "caseCount": len(cases),
        "casesSha256": sha256_json(cases),
        "cases": cases,
    }


def prepare() -> None:
    seeds, metadata, evidence = load_and_verify_sources()
    plan = build_selection(seeds, metadata, evidence)
    plan["normalizationSourceSnapshot"] = load_and_verify_unorm_source()
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    write_json(PLAN_PATH, plan)
    write_sprite(plan["brands"])
    metrics = metrics_for(plan["brands"])
    if metrics["rawAliasCount"] < MINIMUM_ALIASES:
        raise SystemExit(
            f"Sourced raw aliases {metrics['rawAliasCount']} below {MINIMUM_ALIASES}"
        )
    print(json.dumps(metrics, ensure_ascii=False, sort_keys=True))


def write_sprite(entries: list[dict]) -> None:
    rows = (len(entries) + SPRITE_COLUMNS - 1) // SPRITE_COLUMNS
    cells: list[str] = []
    layout: list[dict] = []
    for index, entry in enumerate(entries):
        row, column = divmod(index, SPRITE_COLUMNS)
        layout.append(
            {"brandId": entry["brandId"], "x": column * SPRITE_CELL, "y": row * SPRITE_CELL}
        )
        if entry["renderMode"] == "mono_brand":
            svg_path = PROJECT_ROOT / entry["originalSvgPath"]
            svg = svg_path.read_text(encoding="utf-8")
            svg = re.sub(r"<title>.*?</title>", "", svg, flags=re.DOTALL)
            cells.append(f'<div class="cell simple">{svg}</div>')
        else:
            monogram = html.escape(entry["monogramText"])
            cells.append(f'<div class="cell mono">{monogram}</div>')
    document = f"""<!doctype html>
<meta charset="utf-8">
<style>
html,body{{margin:0;padding:0;width:{SPRITE_COLUMNS * SPRITE_CELL}px;height:{rows * SPRITE_CELL}px;background:transparent;overflow:hidden}}
body{{display:grid;grid-template-columns:repeat({SPRITE_COLUMNS},{SPRITE_CELL}px);grid-auto-rows:{SPRITE_CELL}px}}
.cell{{width:{SPRITE_CELL}px;height:{SPRITE_CELL}px;display:flex;align-items:center;justify-content:center;color:#fff;background:transparent}}
.simple svg{{width:88px;height:88px;display:block;fill:#fff!important;color:#fff!important}}
.simple path{{fill:#fff!important}}
.mono{{font:800 40px/1 Arial,sans-serif;letter-spacing:-1px;color:#fff}}
</style>
{''.join(cells)}
"""
    SPRITE_PATH.write_text(document, encoding="utf-8")
    write_json(
        LAYOUT_PATH,
        {
            "cellSize": SPRITE_CELL,
            "columns": SPRITE_COLUMNS,
            "rows": rows,
            "width": SPRITE_COLUMNS * SPRITE_CELL,
            "height": rows * SPRITE_CELL,
            "entries": layout,
        },
    )


def finalize(generated_at_utc: str) -> None:
    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    normalization_source = load_and_verify_unorm_source()
    if plan.get("normalizationSourceSnapshot") != normalization_source:
        raise SystemExit("Prepared unorm_dart source evidence is stale")
    entries = plan["brands"]
    missing = []
    for entry in entries:
        # Runtime paths are relative to the Flutter app, not the project root.
        asset = APP_DIR / entry["assetPath"]
        if not asset.is_file():
            missing.append(str(asset))
            continue
        entry["assetSha256"] = sha256(asset)
        entry["assetBytes"] = asset.stat().st_size
    if missing:
        raise SystemExit(f"Missing rendered assets: {missing[:5]} ({len(missing)} total)")

    runtime = {
        "schemaVersion": 1,
        "catalogVersion": "simple-icons-16.28.0-cardock-v1",
        "normalizationPolicy": NORMALIZATION_POLICY,
        "brands": [runtime_entry(entry) for entry in entries],
    }
    write_json(RUNTIME_PATH, runtime)
    unorm_license = (UNORM_ROOT / "LICENSE").read_text(encoding="utf-8").strip()
    notice = (
        "Cardock offline brand identification assets\n\n"
        "Selected monochrome artwork is derived from Simple Icons 16.28.0, "
        "distributed under CC0-1.0. Third-party names and marks remain the "
        "property of their respective owners. Their appearance is solely for "
        "identifying user-entered services and does not imply affiliation, "
        "authorization, sponsorship, or endorsement. Entries marked monogram "
        "are neutral Cardock-generated fallbacks and are not official logos.\n\n"
        "Runtime brand-name normalization uses unorm_dart 0.3.2 under the MIT "
        "License. Its locked source evidence is recorded in "
        "manifests/cardock-unorm-dart-source.json.\n\n"
        f"{unorm_license}\n"
    )
    NOTICE_PATH.write_text(notice, encoding="utf-8")

    metrics = metrics_for(entries)
    normalization_parity = normalization_parity_payload(entries)
    asset_total = sum(entry["assetBytes"] for entry in entries)
    metrics.update(
        {
            "assetBytes": asset_total,
            "runtimeCatalogBytes": RUNTIME_PATH.stat().st_size,
            "noticeBytes": NOTICE_PATH.stat().st_size,
            "runtimeCatalogSha256": sha256(RUNTIME_PATH),
            "noticeSha256": sha256(NOTICE_PATH),
            "normalizationParityCaseCount": normalization_parity["caseCount"],
        }
    )
    master = {
        **plan,
        "generatedAtUtc": generated_at_utc,
        "metrics": metrics,
        "normalizationParity": normalization_parity,
        "runtimeCatalogPath": str(RUNTIME_PATH.relative_to(PROJECT_ROOT)).replace("\\", "/"),
    }
    write_json(MASTER_PATH, master)
    write_json(
        VALIDATION_PATH,
        {
            "schemaVersion": 1,
            "generatedAtUtc": generated_at_utc,
            "status": "generated_pending_audit",
            "metrics": metrics,
            "masterManifestSha256": sha256(MASTER_PATH),
            "sourceLockSha256": sha256(LOCK_PATH),
            "normalizationPolicy": NORMALIZATION_POLICY,
            "normalizationParityPath": str(
                NORMALIZATION_PARITY_PATH.relative_to(PROJECT_ROOT)
            ).replace("\\", "/"),
            "normalizationParityStatus": "pending",
            "normalizationSourceManifestSha256": normalization_source[
                "sourceManifestSha256"
            ],
            "pubspecLockSha256": normalization_source["pubspecLockSha256"],
        },
    )
    print(json.dumps(metrics, ensure_ascii=False, sort_keys=True))


def runtime_entry(entry: dict) -> dict:
    value = {
        key: entry[key]
        for key in (
            "brandId", "canonicalName", "aliases", "ambiguousAliases", "categories",
            "regions", "assetPath", "assetFormat", "renderMode", "brandColor",
            "opticalScale", "minimumRenderableDp", "monogramText",
            "trademarkAuthorization",
        )
    }
    value["sourceKind"] = (
        "simple_icons_cc0" if entry["renderMode"] == "mono_brand" else "cardock_generated_monogram"
    )
    return value


def metrics_for(entries: list[dict]) -> dict:
    return {
        "brandCount": len(entries),
        "rawAliasCount": sum(len(entry["aliases"]) for entry in entries),
        "distinctRawAliasCount": len(
            {alias for entry in entries for alias in entry["aliases"]}
        ),
        "distinctNormalizedAliasCount": len(
            {normalize(alias) for entry in entries for alias in entry["aliases"] if normalize(alias)}
        ),
        "seedCount": sum(entry["selectionOrigin"] == "user_v5_seed" for entry in entries),
        "simpleIconsAssetCount": sum(entry["renderMode"] == "mono_brand" for entry in entries),
        "monogramAssetCount": sum(entry["renderMode"] == "monogram" for entry in entries),
        "fullColorCount": sum(bool(entry["fullColor"]) for entry in entries),
        "ambiguousRawAliasCount": sum(len(entry["ambiguousAliases"]) for entry in entries),
        "categoryCounts": dict(sorted(Counter(entry["categories"][0] for entry in entries).items())),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("prepare")
    finalize_parser = subparsers.add_parser("finalize")
    finalize_parser.add_argument("--generated-at-utc", required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        prepare()
    else:
        finalize(args.generated_at_utc)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"FAIL {type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(1) from error
