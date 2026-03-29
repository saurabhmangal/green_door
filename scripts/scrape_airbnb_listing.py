#!/usr/bin/env python3
"""Extract Airbnb listing metadata from a public listing page.

This script fetches the Airbnb page HTML and attempts to pull listing details
from embedded JSON payloads and JSON-LD metadata.

Usage:
    python scripts/scrape_airbnb_listing.py \
        "https://www.airbnb.co.in/rooms/629898381570822700" \
        --output scraped-airbnb.json
"""

import argparse
import json
import re
import sys
import urllib.request
from html import unescape

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
}


def fetch_html(url):
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="ignore")


def find_balanced_json(text, start_index):
    depth = 0
    in_string = False
    escape = False
    i = start_index
    while i < len(text):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == "\"":
                in_string = False
        else:
            if ch == "\"":
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[start_index : i + 1]
        i += 1
    return None


def extract_json_from_assignment(html, key_name):
    marker = f"{key_name}" + "\s*=\s*{"
    match = re.search(re.escape(key_name) + r"\s*=\s*\{", html)
    if not match:
        return None
    start = html.find("{", match.end() - 1)
    if start < 0:
        return None
    candidate = find_balanced_json(html, start)
    if not candidate:
        return None
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        return None


def extract_json_ld(html):
    for script_match in re.finditer(
        r"<script[^>]+type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>",
        html,
        flags=re.I | re.S,
    ):
        payload = script_match.group(1).strip()
        if not payload:
            continue
        try:
            data = json.loads(payload)
            if isinstance(data, list) and data:
                return data[0]
            return data
        except json.JSONDecodeError:
            try:
                data = json.loads(unescape(payload))
                if isinstance(data, list) and data:
                    return data[0]
                return data
            except json.JSONDecodeError:
                continue
    return None


def recursive_search(obj, key_predicate=None, value_predicate=None, max_depth=8):
    if max_depth < 0:
        return None
    if isinstance(obj, dict):
        if key_predicate:
            for key, value in obj.items():
                if key_predicate(key, value):
                    return value
        if value_predicate and value_predicate(obj):
            return obj
        for value in obj.values():
            found = recursive_search(value, key_predicate, value_predicate, max_depth - 1)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for item in obj:
            found = recursive_search(item, key_predicate, value_predicate, max_depth - 1)
            if found is not None:
                return found
    return None


def safe_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def safe_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def extract_listing_metadata(page_json, json_ld):
    metadata = {
        "listingUrl": None,
        "source": "Airbnb",
        "name": None,
        "id": None,
        "bedrooms": None,
        "maxGuests": None,
        "hasPool": None,
        "walkMinutesToBeach": None,
        "rating": None,
        "reviewCount": None,
        "description": None,
        "raw": {},
    }

    if json_ld and isinstance(json_ld, dict):
        metadata["name"] = metadata["name"] or json_ld.get("name")
        metadata["description"] = metadata["description"] or json_ld.get("description")
        agg = json_ld.get("aggregateRating")
        if isinstance(agg, dict):
            metadata["rating"] = safe_float(agg.get("ratingValue")) or metadata["rating"]
            metadata["reviewCount"] = safe_int(agg.get("reviewCount")) or metadata["reviewCount"]
        if json_ld.get("@type") in ("LodgingBusiness", "Apartment"):
            metadata["raw"]["json_ld"] = json_ld

    if page_json:
        metadata["raw"]["page_json"] = page_json
        listing_obj = recursive_search(
            page_json,
            key_predicate=lambda key, value: key in ("listing", "listingInfo", "listing_details") and isinstance(value, dict),
            max_depth=10,
        )
        if isinstance(listing_obj, dict):
            metadata["id"] = metadata["id"] or listing_obj.get("id")
            metadata["name"] = metadata["name"] or listing_obj.get("name") or listing_obj.get("title")
            metadata["description"] = metadata["description"] or listing_obj.get("description")
            metadata["bedrooms"] = metadata["bedrooms"] or safe_int(listing_obj.get("bedrooms") or listing_obj.get("bedroom_count"))
            metadata["maxGuests"] = metadata["maxGuests"] or safe_int(
                listing_obj.get("person_capacity")
                or listing_obj.get("personCapacity")
                or listing_obj.get("guests_included")
                or listing_obj.get("max_guests")
                or listing_obj.get("maxGuests")
            )
            metadata["rating"] = metadata["rating"] or safe_float(listing_obj.get("rating"))
            if metadata["hasPool"] is None:
                amenities = listing_obj.get("amenities") or listing_obj.get("listing_amenities")
                if isinstance(amenities, list):
                    pool_tokens = [str(x).lower() for x in amenities]
                    metadata["hasPool"] = any("pool" in token for token in pool_tokens)
        else:
            candidate = recursive_search(
                page_json,
                value_predicate=lambda value: isinstance(value, dict) and value.get("listing_id") and value.get("name"),
                max_depth=10,
            )
            if isinstance(candidate, dict):
                metadata["id"] = metadata["id"] or candidate.get("listing_id")
                metadata["name"] = metadata["name"] or candidate.get("name")
                metadata["description"] = metadata["description"] or candidate.get("description")
                metadata["bedrooms"] = metadata["bedrooms"] or safe_int(candidate.get("bedrooms"))
                metadata["maxGuests"] = metadata["maxGuests"] or safe_int(candidate.get("person_capacity") or candidate.get("max_guests"))
                metadata["rating"] = metadata["rating"] or safe_float(candidate.get("star_rating") or candidate.get("rating"))

        if metadata["hasPool"] is None:
            pool_match = recursive_search(
                page_json,
                value_predicate=lambda value: isinstance(value, dict) and "pool" in str(value).lower() and "amenities" in value,
                max_depth=8,
            )
            if isinstance(pool_match, dict):
                metadata["hasPool"] = True

    if metadata["name"] is None and json_ld and isinstance(json_ld, dict):
        metadata["name"] = json_ld.get("name")

    return metadata


def extract_airbnb_listing(url):
    html = fetch_html(url)
    json_ld = extract_json_ld(html)
    page_json = extract_json_from_assignment(html, "window.__INITIAL_STATE__")
    if page_json is None:
        page_json = extract_json_from_assignment(html, "window.__PRELOADED_STATE__")
    if page_json is None:
        page_json = extract_json_from_assignment(html, "__INITIAL_STATE__")

    metadata = extract_listing_metadata(page_json, json_ld)
    metadata["listingUrl"] = url

    if metadata["id"] is None:
        listing_id = None
        match = re.search(r"/rooms/(\d+)", url)
        if match:
            listing_id = match.group(1)
        metadata["id"] = listing_id

    if metadata["hasPool"] is None:
        metadata["hasPool"] = False

    return metadata


def write_json(data, output_path):
    with open(output_path, "w", encoding="utf-8") as output_file:
        json.dump(data, output_file, indent=2, ensure_ascii=False)


def parse_arguments():
    parser = argparse.ArgumentParser(description="Scrape Airbnb listing metadata into JSON.")
    parser.add_argument("url", help="Public Airbnb listing URL")
    parser.add_argument(
        "--output",
        default="scraped-airbnb-listing.json",
        help="Path to write the extracted JSON file",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_arguments()
    try:
        scraped = extract_airbnb_listing(args.url)
        write_json(scraped, args.output)
        print(f"Wrote scraped listing metadata to {args.output}")
    except Exception as error:
        print(f"Error scraping Airbnb listing: {error}", file=sys.stderr)
        sys.exit(1)
