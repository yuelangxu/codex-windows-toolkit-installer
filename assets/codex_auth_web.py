import argparse
import io
import json
import os
import random
import re
import shutil
import sys
import time
import zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple
from urllib.parse import parse_qs, unquote, urljoin, urlparse

import requests
from bs4 import BeautifulSoup, Tag
from playwright.sync_api import sync_playwright

COMMON_FILE_EXTENSIONS = {
    ".7z", ".avi", ".bib", ".csv", ".doc", ".docm", ".docx", ".epub", ".gif", ".gz", ".html",
    ".ipynb", ".jpeg", ".jpg", ".json", ".key", ".m4a", ".md", ".mov", ".mp3", ".mp4", ".mpeg",
    ".odp", ".ods", ".odt", ".pdf", ".png", ".ppt", ".pptm", ".pptx", ".ps", ".py", ".rar",
    ".rtf", ".tar", ".tex", ".tgz", ".tsv", ".txt", ".wav", ".webm", ".xls", ".xlsm", ".xlsx",
    ".xml", ".yaml", ".yml", ".zip",
}

NAVIGATION_TEXT = {
    "", "home", "profile", "preferences", "privacy", "search", "back to top",
    "settings", "calendar", "courses", "my courses", "grades", "reports",
    "log out", "logout", "contacts", "notifications settings",
}

CHATGPT_HOSTS = {"chatgpt.com", "chat.openai.com"}
DEFAULT_STUDY_KEYWORDS = [
    "study", "learning", "learn", "course", "lecture", "lectures", "lecture note", "notes",
    "homework", "assignment", "problem set", "worksheet", "exam", "quiz", "revision", "revise",
    "moodle", "university", "ucl", "paper", "essay", "dissertation", "lab", "physics", "math",
    "mathematics", "calculus", "algebra", "python", "coding interview", "research", "flashcards",
    "学习", "课程", "讲义", "笔记", "作业", "考试", "复习", "论文", "实验", "物理", "数学", "编程",
]

CHATGPT_GUARD_PHRASES = [
    "unusual activity",
    "try again later",
    "too many requests",
    "making requests too quickly",
    "temporarily unavailable",
    "temporarily blocked",
    "temporarily limited access to your conversations",
    "request blocked",
    "verify you are human",
    "checking your browser",
    "access denied",
    "our systems have detected",
    "temporary chat",
]

CHATGPT_BROAD_KEYWORDS = {
    "study", "learning", "learn", "note", "notes", "course", "courses", "lecture", "lectures",
    "assignment", "university", "ucl", "physics", "math", "mathematics", "research", "paper",
    "essay", "coding", "python", "car", "cars", "flower", "flowers", "garden",
}

CHATGPT_RATE_LIMIT_STATE_PATH = Path.home() / ".codex" / "web-auth-state" / "chatgpt_rate_limit.json"
CLI_TEXT_PREVIEW_MAX_CHARS = 12000
CHATGPT_DESKTOP_VIEWPORT = {"width": 1440, "height": 1100}
CHATGPT_RUNTIME_PREPARED_PAGES: Set[int] = set()


def sanitize(name: str, max_len: int = 160) -> str:
    value = re.sub(r"\s+", " ", (name or "").strip())
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value)
    value = value.rstrip(" .")
    if not value:
        value = "untitled"
    if len(value) > max_len:
        value = value[:max_len].rstrip(" ._")
    return value


def ensure_parent(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def write_text(path: Path, text: str) -> None:
    ensure_parent(path)
    path.write_text(text, encoding="utf-8")


def ensure_existing_directory(path_value: str, label: str) -> Path:
    path = Path(path_value).expanduser().resolve()
    if not path.exists():
        raise RuntimeError(f"{label} does not exist: {path}")
    if not path.is_dir():
        raise RuntimeError(f"{label} is not a directory: {path}")
    return path


def ensure_directory(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def slugify_extension_name(name: str) -> str:
    value = sanitize(name or "extension", max_len=80).lower()
    value = re.sub(r"[^a-z0-9._-]+", "-", value)
    value = value.strip("._-")
    return value or "extension"


def get_browser_extensions_manager_url(browser: str) -> str:
    return "edge://extensions/" if clean_text(browser).lower() == "edge" else "chrome://extensions/"


def ensure_clean_directory(path: Path, overwrite: bool = False) -> Path:
    if path.exists():
        if not overwrite:
            raise RuntimeError(f"Path already exists: {path}")
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    path.mkdir(parents=True, exist_ok=True)
    return path


def find_extension_manifest_root(search_root: Path) -> Path:
    direct_manifest = search_root / "manifest.json"
    if direct_manifest.exists():
        return search_root

    manifests = [
        manifest
        for manifest in search_root.rglob("manifest.json")
        if "__MACOSX" not in manifest.parts and ".git" not in manifest.parts and "node_modules" not in manifest.parts
    ]
    if not manifests:
        raise RuntimeError(f"No manifest.json was found under {search_root}")

    manifests.sort(key=lambda item: (len(item.relative_to(search_root).parts), len(str(item))))
    return manifests[0].parent


def inspect_browser_extension_manifest(extension_root: Path) -> Dict[str, Any]:
    manifest_path = extension_root / "manifest.json"
    if not manifest_path.exists():
        raise RuntimeError(f"manifest.json is missing from {extension_root}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    action = manifest.get("action") or manifest.get("browser_action") or manifest.get("page_action") or {}
    options_ui = manifest.get("options_ui") or {}
    return {
        "name": clean_text(str(manifest.get("name") or "")),
        "version": clean_text(str(manifest.get("version") or "")),
        "manifest_version": int(manifest.get("manifest_version") or 0),
        "description": clean_text(str(manifest.get("description") or "")),
        "popup_path": clean_text(str(action.get("default_popup") or "")),
        "options_path": clean_text(str(options_ui.get("page") or manifest.get("options_page") or "")),
        "homepage_url": clean_text(str(manifest.get("homepage_url") or "")),
        "manifest_path": str(manifest_path),
    }


def download_extension_package(url: str, packages_root: Path, slug: str) -> Path:
    ensure_directory(packages_root)
    response = requests.get(url, stream=True, timeout=180)
    response.raise_for_status()
    fallback_name = sanitize(Path(urlparse(url).path).name or f"{slug}.zip")
    output_name = filename_from_response(url, dict(response.headers), fallback_name)
    destination = packages_root / output_name
    with destination.open("wb") as handle:
        for chunk in response.iter_content(chunk_size=1024 * 1024):
            if chunk:
                handle.write(chunk)
    return destination


def extract_crx_payload(package_path: Path) -> bytes:
    payload = package_path.read_bytes()
    if payload[:4] != b"Cr24":
        raise RuntimeError(f"Not a valid Chromium CRX archive: {package_path}")

    version = int.from_bytes(payload[4:8], "little")
    if version == 3:
        header_size = int.from_bytes(payload[8:12], "little")
        zip_start = 12 + header_size
    elif version == 2:
        public_key_size = int.from_bytes(payload[8:12], "little")
        signature_size = int.from_bytes(payload[12:16], "little")
        zip_start = 16 + public_key_size + signature_size
    else:
        raise RuntimeError(f"Unsupported CRX version {version} in {package_path}")

    return payload[zip_start:]


def unpack_extension_archive(package_path: Path, destination_root: Path) -> None:
    suffix = package_path.suffix.lower()
    if suffix == ".zip":
        with zipfile.ZipFile(package_path) as archive:
            archive.extractall(destination_root)
        return

    if suffix == ".crx":
        zip_payload = extract_crx_payload(package_path)
        with zipfile.ZipFile(io.BytesIO(zip_payload)) as archive:
            archive.extractall(destination_root)
        return

    raise RuntimeError(f"Unsupported extension package type: {package_path.suffix}")


def write_shortcut(path: Path, url: str) -> None:
    write_text(path, f"[InternetShortcut]\nURL={url}\n")


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", (value or "").strip())


def env_float(name: str, default: float) -> float:
    raw = clean_text(os.environ.get(name, ""))
    if not raw:
        return default
    try:
        return float(raw)
    except Exception:
        return default


def env_int(name: str, default: int) -> int:
    raw = clean_text(os.environ.get(name, ""))
    if not raw:
        return default
    try:
        return int(raw)
    except Exception:
        return default


def compact_text_for_cli(text: str, max_chars: int = CLI_TEXT_PREVIEW_MAX_CHARS) -> Tuple[str, bool]:
    value = text or ""
    if len(value) <= max_chars:
        return value, False

    notice = "\n...[truncated in CLI output; see saved file for the full text]"
    keep = max(0, max_chars - len(notice))
    clipped = value[:keep].rstrip()
    return f"{clipped}{notice}", True


def resolve_chatgpt_prompt_text(args) -> str:
    prompt_sources = []
    prompt_text = clean_text(getattr(args, "prompt", ""))
    prompt_file = clean_text(getattr(args, "prompt_file", ""))
    prompt_stdin = bool(getattr(args, "prompt_stdin", False))

    if prompt_text:
        prompt_sources.append("prompt")
    if prompt_file:
        prompt_sources.append("prompt-file")
    if prompt_stdin:
        prompt_sources.append("prompt-stdin")

    if not prompt_sources:
        raise RuntimeError("Provide --prompt, --prompt-file, or --prompt-stdin.")
    if len(prompt_sources) > 1:
        raise RuntimeError("Use exactly one prompt source: --prompt, --prompt-file, or --prompt-stdin.")

    if prompt_file:
        return Path(prompt_file).expanduser().resolve().read_text(encoding="utf-8-sig")
    if prompt_stdin:
        return sys.stdin.read()
    return getattr(args, "prompt", "")


def filename_from_response(url: str, headers: Dict[str, str], fallback_name: str) -> str:
    content_disposition = headers.get("content-disposition", "")
    match = re.search(r"""filename\*?=(?:UTF-8'')?"?([^";]+)"?""", content_disposition, re.I)
    if match:
        return sanitize(unquote(match.group(1)))

    parsed = urlparse(url)
    query = parse_qs(parsed.query)
    disposition = query.get("response-content-disposition", [])
    if disposition:
        decoded = unquote(disposition[0])
        match = re.search(r"""filename="?([^";]+)"?""", decoded, re.I)
        if match:
            return sanitize(match.group(1))

    leaf = unquote(os.path.basename(parsed.path))
    if leaf:
        return sanitize(leaf)
    return sanitize(fallback_name)


def connect_browser(cdp_url: str):
    playwright = sync_playwright().start()
    browser = playwright.chromium.connect_over_cdp(cdp_url)
    return playwright, browser


def choose_context(browser):
    if not browser.contexts:
        raise RuntimeError("No browser context found. Start the browser with remote debugging and open the target site first.")
    return browser.contexts[0]


def choose_page(context, page_url_contains: Optional[str] = None, require_existing: bool = False):
    if page_url_contains:
        for page in context.pages:
            if page_url_contains in page.url:
                return page, False
        if require_existing:
            raise RuntimeError(f"No existing page matched: {page_url_contains}")

    if context.pages:
        return context.pages[0], False

    if require_existing:
        raise RuntimeError("No existing page found in the connected browser context.")

    return context.new_page(), True


def read_profile_runtime_browser_extensions(user_data_dir: str, profile_directory: str = "Default") -> List[Dict[str, Any]]:
    if not clean_text(user_data_dir):
        return []

    base_dir = Path(user_data_dir).expanduser().resolve()
    settings_by_id: Dict[str, Dict[str, Any]] = {}
    candidate_files = [
        base_dir / profile_directory / "Secure Preferences",
        base_dir / profile_directory / "Preferences",
    ]

    for candidate in candidate_files:
        if not candidate.exists():
            continue
        try:
            payload = json.loads(candidate.read_text(encoding="utf-8-sig"))
        except Exception:
            continue

        extension_settings = ((payload.get("extensions") or {}).get("settings") or {})
        if not isinstance(extension_settings, dict):
            continue

        for extension_id, entry in extension_settings.items():
            if not isinstance(entry, dict):
                continue
            settings_by_id[str(extension_id)] = entry

    results: List[Dict[str, Any]] = []
    for extension_id, entry in settings_by_id.items():
        manifest = entry.get("manifest") or {}
        disable_reasons = entry.get("disable_reasons") or []
        enabled: Optional[bool] = None
        state_value = entry.get("state")
        if isinstance(state_value, (int, float)):
            enabled = int(state_value) != 0
        elif isinstance(entry.get("enabled"), bool):
            enabled = bool(entry.get("enabled"))
        elif isinstance(disable_reasons, list):
            enabled = len(disable_reasons) == 0

        results.append(
            {
                "id": clean_text(extension_id),
                "name": clean_text(str(manifest.get("name") or entry.get("name") or "")),
                "version": clean_text(str(manifest.get("version") or entry.get("version") or "")),
                "enabled": enabled,
                "description": clean_text(str(manifest.get("description") or entry.get("description") or "")),
                "homepage_url": clean_text(str(manifest.get("homepage_url") or entry.get("homepage_url") or "")),
                "options_page": clean_text(str(manifest.get("options_page") or entry.get("options_page") or "")),
                "path": clean_text(str(entry.get("path") or "")),
                "source": "profile_preferences",
            }
        )

    deduped: List[Dict[str, Any]] = []
    seen = set()
    for item in results:
        key = item["id"] or item["name"].lower()
        if not key or key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped


def list_runtime_browser_extensions(
    page,
    browser: str,
    user_data_dir: str = "",
    profile_directory: str = "Default",
) -> List[Dict[str, Any]]:
    manager_url = get_browser_extensions_manager_url(browser)
    raw_items = []
    try:
        page.goto(manager_url, wait_until="domcontentloaded", timeout=120000)
        page.wait_for_timeout(1200)
        raw_items = page.evaluate(
            """() => {
                const items = [];
                const seenRoots = new Set();
                const queue = [document];
                while (queue.length) {
                    const root = queue.shift();
                    if (!root || seenRoots.has(root)) {
                        continue;
                    }
                    seenRoots.add(root);
                    if (!root.querySelectorAll) {
                        continue;
                    }
                    for (const item of root.querySelectorAll('extensions-item')) {
                        items.push(item);
                    }
                    for (const element of root.querySelectorAll('*')) {
                        if (element.shadowRoot) {
                            queue.push(element.shadowRoot);
                        }
                    }
                }

                const readText = (root, selectors) => {
                    if (!root) {
                        return '';
                    }
                    for (const selector of selectors) {
                        const node = root.querySelector(selector);
                        if (node) {
                            const text = (node.innerText || node.textContent || '').trim();
                            if (text) {
                                return text;
                            }
                        }
                    }
                    return '';
                };

                return items.map(item => {
                    const data = item.data || item.item || item.__data || item.data_ || {};
                    const shadow = item.shadowRoot;
                    let enabled = null;
                    if (typeof data.state !== 'undefined') {
                        enabled = Number(data.state) !== 0;
                    } else if (typeof data.enabled !== 'undefined') {
                        enabled = !!data.enabled;
                    }

                    const id = String(data.id || item.getAttribute('id') || item.dataset.extensionId || '').trim();
                    const name = String(data.name || readText(shadow, ['#name', '.name', '[id=\"name\"]']) || '').trim();
                    const version = String(data.version || '').trim();
                    const description = String(data.description || readText(shadow, ['#description', '.description']) || '').trim();
                    const homepageUrl = String(data.homePage || data.homepageUrl || '').trim();
                    const optionsPage = String(data.optionsPage || data.optionsUrl || '').trim();
                    return {
                        id,
                        name,
                        version,
                        enabled,
                        description,
                        homepage_url: homepageUrl,
                        options_page: optionsPage,
                        source: 'manager_page',
                    };
                }).filter(item => item.id || item.name);
            }"""
        )
    except Exception:
        raw_items = []

    results: List[Dict[str, Any]] = []
    seen = set()
    for item in raw_items or []:
        normalized = {
            "id": clean_text(str(item.get("id") or "")),
            "name": clean_text(str(item.get("name") or "")),
            "version": clean_text(str(item.get("version") or "")),
            "enabled": item.get("enabled"),
            "description": clean_text(str(item.get("description") or "")),
            "homepage_url": clean_text(str(item.get("homepage_url") or "")),
            "options_page": clean_text(str(item.get("options_page") or "")),
            "source": clean_text(str(item.get("source") or "manager_page")),
        }
        key = normalized["id"] or normalized["name"].lower()
        if not key or key in seen:
            continue
        seen.add(key)
        results.append(normalized)

    for item in read_profile_runtime_browser_extensions(user_data_dir, profile_directory):
        key = item["id"] or item["name"].lower()
        if not key or key in seen:
            continue
        seen.add(key)
        results.append(item)
    return results


def find_runtime_browser_extension(
    entries: List[Dict[str, Any]],
    extension_id: str = "",
    name: str = "",
) -> Dict[str, Any]:
    if extension_id:
        needle = clean_text(extension_id).lower()
        for entry in entries:
            if clean_text(entry.get("id") or "").lower() == needle:
                return entry
        raise RuntimeError(f"No browser extension matched id {extension_id}")

    if name:
        exact = clean_text(name).lower()
        exact_matches = [entry for entry in entries if clean_text(entry.get("name") or "").lower() == exact]
        if exact_matches:
            return exact_matches[0]

        contains_matches = [entry for entry in entries if exact and exact in clean_text(entry.get("name") or "").lower()]
        if contains_matches:
            return contains_matches[0]

    raise RuntimeError("No browser extension matched the requested name or id.")


def build_runtime_extension_url(extension_id: str, page_path: str = "", url: str = "") -> str:
    if url:
        return url

    normalized_path = clean_text(page_path).lstrip("/")
    if not normalized_path:
        raise RuntimeError("An extension page path or URL is required.")
    return f"chrome-extension://{extension_id}/{normalized_path}"


def find_visible_page_control(page, selector: str = "", text_contains: str = ""):
    if selector:
        locator = page.locator(selector)
        if locator.count() == 0:
            raise RuntimeError(f"No element matched selector: {selector}")
        return locator.first, selector

    needle = clean_text(text_contains).lower()
    if not needle:
        raise RuntimeError("A selector or visible text fragment is required.")

    selectors = [
        "button",
        "[role='button']",
        "a",
        "summary",
        "input[type='button']",
        "input[type='submit']",
    ]
    for selector in selectors:
        locator = page.locator(selector)
        count = min(locator.count(), 80)
        for index in range(count):
            candidate = locator.nth(index)
            try:
                if not candidate.is_visible(timeout=300):
                    continue
                label = clean_text(
                    " ".join(
                        [
                            candidate.get_attribute("aria-label") or "",
                            candidate.get_attribute("title") or "",
                            candidate.get_attribute("value") or "",
                            candidate.inner_text(timeout=500) or "",
                        ]
                    )
                )
                if label and needle in label.lower():
                    return candidate, label
            except Exception:
                continue

    raise RuntimeError(f"No visible control contained text: {text_contains}")


def normalize_links(raw_links: List[Dict[str, str]]) -> List[Dict[str, str]]:
    seen = set()
    result = []
    for item in raw_links:
        href = item.get("href", "").strip()
        text = re.sub(r"\s+", " ", (item.get("text") or "").strip())
        title = re.sub(r"\s+", " ", (item.get("title") or "").strip())
        key = (href, text, title)
        if not href or key in seen:
            continue
        seen.add(key)
        result.append({"href": href, "text": text, "title": title})
    return result


def clean_title_for_root(title: str) -> str:
    value = re.sub(r"\s+\|\s+[^|]+$", "", (title or "").strip())
    value = re.sub(r"^(Course:\s*)", "", value, flags=re.I)
    value = re.sub(r"\s+", " ", value).strip()
    return sanitize(value)


def get_url_host(url: str) -> str:
    try:
        return (urlparse(url).netloc or "").lower()
    except Exception:
        return ""


def get_url_path(url: str) -> str:
    try:
        return (urlparse(url).path or "").lower()
    except Exception:
        return ""


def is_probable_file_link(href: str, text: str = "") -> bool:
    href_lc = (href or "").lower()
    text_lc = (text or "").lower()
    path = get_url_path(href_lc)

    if "forcedownload=1" in href_lc or "download=1" in href_lc or "download.aspx" in href_lc:
        return True
    if "pluginfile.php" in href_lc:
        return True

    _, ext = os.path.splitext(path)
    if ext in COMMON_FILE_EXTENSIONS:
        return True

    text_match = re.search(r"\.[a-z0-9]{2,5}\b", text_lc)
    if text_match and text_match.group(0) in COMMON_FILE_EXTENSIONS:
        return True

    return False


def is_page_like_link(href: str) -> bool:
    href_lc = (href or "").lower()
    path = get_url_path(href_lc)
    if href_lc.endswith("#") or "#" in href_lc and href_lc.split("#", 1)[0] == href_lc.split("#", 1)[0]:
        return False
    if path.endswith((".html", ".htm", ".aspx", ".php")):
        return True
    if "/sitepages/" in path or "/pages/" in path or "/wiki/" in path:
        return True
    return False


def looks_like_navigation_link(link: Dict[str, str], page_host: str) -> bool:
    href = link.get("href", "")
    text = (link.get("text") or "").strip().lower()
    title = (link.get("title") or "").strip().lower()

    if not href:
        return True
    if href.startswith(("javascript:", "mailto:", "tel:")):
        return True

    parsed = urlparse(href)
    if parsed.fragment and not parsed.path and not parsed.query:
        return True
    if text in NAVIGATION_TEXT or title in NAVIGATION_TEXT:
        return True
    if not text and not title:
        return True

    link_host = get_url_host(href)
    if page_host and link_host and link_host != page_host and not is_probable_file_link(href, text):
        return False

    return False


def page_links_payload(page) -> Dict[str, Any]:
    payload = page.evaluate(
        """() => {
            const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
            const links = [...document.querySelectorAll('a[href]')].map(anchor => ({
                href: anchor.href || '',
                text: clean(anchor.innerText || anchor.textContent || ''),
                title: clean(anchor.title || '')
            }));
            return {
                title: document.title,
                url: location.href,
                links
            };
        }"""
    )
    payload["links"] = normalize_links(payload.get("links", []))
    return payload


def normalize_keyword_list(raw_keywords: Optional[List[str]], fallback_keywords: Optional[List[str]] = None) -> List[str]:
    values = raw_keywords or fallback_keywords or []
    keywords: List[str] = []
    seen = set()
    for raw in values:
        for part in re.split(r"[;,]", raw or ""):
            keyword = clean_text(part)
            if not keyword:
                continue
            lowered = keyword.lower()
            if lowered in seen:
                continue
            seen.add(lowered)
            keywords.append(keyword)
    return keywords


def build_chatgpt_risk_report(
    keywords: Optional[List[str]],
    topic_label: str,
    save_all: bool,
    use_study_keywords: bool,
    explicit_limit: Optional[int],
) -> Dict[str, Any]:
    keyword_list = normalize_keyword_list(keywords)
    warnings: List[str] = []
    risk_level = "low"
    suggested_limit = 0

    broad_hits = []
    for keyword in keyword_list:
        lowered = keyword.lower()
        if lowered in CHATGPT_BROAD_KEYWORDS or len(lowered) <= 3:
            broad_hits.append(keyword)

    if save_all:
        risk_level = "very_high"
        suggested_limit = 8
        warnings.append("Save-all mode is the broadest mode and is most likely to trigger temporary ChatGPT protections.")

    if use_study_keywords:
        if risk_level in {"low", "medium"}:
            risk_level = "high"
        suggested_limit = max(suggested_limit, 20)
        warnings.append("The built-in learning template uses broad keywords and can match a large part of chat history.")

    if broad_hits:
        if risk_level == "low":
            risk_level = "medium"
        elif risk_level == "medium":
            risk_level = "high"
        suggested_limit = max(suggested_limit, 20)
        warnings.append(f"Broad/generic keywords detected: {', '.join(broad_hits[:8])}")

    if len(keyword_list) >= 8:
        if risk_level in {"low", "medium"}:
            risk_level = "high"
        suggested_limit = max(suggested_limit, 25)
        warnings.append("A large keyword list can still fan out to many conversations.")

    auto_limited = False
    effective_limit = explicit_limit if explicit_limit and explicit_limit > 0 else None
    if effective_limit is None and suggested_limit > 0:
        effective_limit = suggested_limit
        auto_limited = True
        warnings.append(
            f"No explicit limit was supplied for topic '{clean_text(topic_label) or 'topic'}'. "
            f"A safer sample limit of {effective_limit} will be applied automatically."
        )
    elif effective_limit is not None and suggested_limit > 0 and effective_limit > suggested_limit * 2:
        warnings.append(
            f"The requested limit ({effective_limit}) is much higher than the safer sample size ({suggested_limit}) "
            "and may increase the chance of temporary restrictions."
        )

    return {
        "risk_level": risk_level,
        "warnings": dedupe_strings(warnings),
        "suggested_limit": suggested_limit,
        "effective_limit": effective_limit,
        "auto_limited": auto_limited,
    }


def detect_chatgpt_guard_signal(page) -> Optional[Dict[str, str]]:
    url = page.url or ""
    url_lc = url.lower()
    if any(token in url_lc for token in ["/auth/error", "/blocked", "/sorry", "cloudflare"]):
        return {"kind": "url", "signal": url}

    body_text = ""
    try:
        body_text = clean_text(page.locator("body").inner_text(timeout=2500))
    except Exception:
        return None

    body_lc = body_text.lower()
    for phrase in CHATGPT_GUARD_PHRASES:
        if phrase in body_lc:
            return {"kind": "text", "signal": phrase}
    return None


def chatgpt_iteration_delay_seconds(risk_level: str) -> float:
    if risk_level in {"high", "very_high"}:
        return random.uniform(2.5, 3.5)
    if risk_level == "medium":
        return random.uniform(1.9, 2.7)
    return random.uniform(1.4, 2.0)


def get_chatgpt_rate_limit_config() -> Dict[str, float]:
    browse_delay = max(0.0, env_float("CODEX_CHATGPT_BROWSE_DELAY_SECONDS", 1.625))
    mutation_delay = max(browse_delay, env_float("CODEX_CHATGPT_MUTATION_DELAY_SECONDS", 4.5))
    jitter_delay = max(0.0, env_float("CODEX_CHATGPT_DELAY_JITTER_SECONDS", 0.625))
    return {
        "browse_delay": browse_delay,
        "mutation_delay": mutation_delay,
        "jitter_delay": jitter_delay,
    }


def read_chatgpt_rate_limit_state() -> Dict[str, Any]:
    path = CHATGPT_RATE_LIMIT_STATE_PATH
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {}


def write_chatgpt_rate_limit_state(state: Dict[str, Any]) -> None:
    ensure_parent(CHATGPT_RATE_LIMIT_STATE_PATH)
    CHATGPT_RATE_LIMIT_STATE_PATH.write_text(json.dumps(state, indent=2, ensure_ascii=False), encoding="utf-8")


def throttle_chatgpt_request(category: str, reason: str = "") -> Dict[str, Any]:
    config = get_chatgpt_rate_limit_config()
    min_delay = config["mutation_delay"] if clean_text(category).lower() == "mutation" else config["browse_delay"]
    state = read_chatgpt_rate_limit_state()
    now = time.time()
    previous = float(state.get("last_request_ts") or 0.0)
    elapsed = max(0.0, now - previous)
    wait_seconds = max(0.0, min_delay - elapsed)
    if wait_seconds > 0:
        wait_seconds += random.uniform(0.0, config["jitter_delay"])
        time.sleep(wait_seconds)

    applied_at = time.time()
    write_chatgpt_rate_limit_state(
        {
            "last_request_ts": applied_at,
            "last_category": clean_text(category).lower() or "browse",
            "last_reason": clean_text(reason),
            "configured_browse_delay": config["browse_delay"],
            "configured_mutation_delay": config["mutation_delay"],
            "configured_jitter_delay": config["jitter_delay"],
        }
    )
    return {
        "category": clean_text(category).lower() or "browse",
        "slept_seconds": round(wait_seconds, 3),
        "min_delay_seconds": min_delay,
        "reason": clean_text(reason),
    }


def get_chatgpt_guard_cooldown_seconds() -> float:
    return max(0.5, env_float("CODEX_CHATGPT_GOT_IT_COOLDOWN_SECONDS", 4.5))


def get_chatgpt_sidebar_settle_seconds() -> float:
    return max(0.25, env_float("CODEX_CHATGPT_SIDEBAR_SETTLE_SECONDS", 1.0))


def get_chatgpt_post_action_settle_seconds() -> float:
    return max(0.2, env_float("CODEX_CHATGPT_POST_ACTION_SETTLE_SECONDS", 0.75))


def get_chatgpt_poll_interval_seconds() -> float:
    return max(0.2, env_float("CODEX_CHATGPT_POLL_INTERVAL_SECONDS", 0.5))


def wait_chatgpt_sidebar_settle(page, multiplier: float = 1.0) -> None:
    page.wait_for_timeout(int(get_chatgpt_sidebar_settle_seconds() * 1000 * max(0.1, multiplier)))


def wait_chatgpt_post_action_settle(page, multiplier: float = 1.0) -> None:
    page.wait_for_timeout(int(get_chatgpt_post_action_settle_seconds() * 1000 * max(0.1, multiplier)))


def is_retryable_chatgpt_navigation_error(exc: Exception) -> bool:
    message = clean_text(str(exc)).lower()
    return "net::err_aborted" in message or "err_aborted" in message


def navigate_chatgpt(page, url: str, wait_until: str = "domcontentloaded", timeout: int = 120000, attempts: int = 3) -> None:
    last_exc: Optional[Exception] = None
    for attempt in range(max(1, attempts)):
        try:
            page.goto(url, wait_until=wait_until, timeout=timeout)
            return
        except Exception as exc:
            last_exc = exc
            if not is_retryable_chatgpt_navigation_error(exc) or attempt >= attempts - 1:
                raise
            page.wait_for_timeout(900 + attempt * 700)

    if last_exc is not None:
        raise last_exc


def reload_chatgpt(page, wait_until: str = "domcontentloaded", timeout: int = 120000, attempts: int = 3) -> None:
    last_exc: Optional[Exception] = None
    for attempt in range(max(1, attempts)):
        try:
            page.reload(wait_until=wait_until, timeout=timeout)
            return
        except Exception as exc:
            last_exc = exc
            if not is_retryable_chatgpt_navigation_error(exc) or attempt >= attempts - 1:
                raise
            page.wait_for_timeout(900 + attempt * 700)

    if last_exc is not None:
        raise last_exc


def refresh_chatgpt_page(page, reason: str = "", target_url: Optional[str] = None) -> Dict[str, Any]:
    refresh_url = clean_text(target_url or page.url or "https://chatgpt.com/")
    if get_url_host(refresh_url) not in CHATGPT_HOSTS:
        refresh_url = "https://chatgpt.com/"

    throttle_chatgpt_request("browse", f"refresh:{clean_text(reason) or refresh_url}")
    try:
        current_url = clean_text(page.url or "")
        if current_url and current_url == refresh_url:
            reload_chatgpt(page, wait_until="domcontentloaded", timeout=120000)
        else:
            navigate_chatgpt(page, refresh_url, wait_until="domcontentloaded", timeout=120000)
    except Exception:
        navigate_chatgpt(page, refresh_url, wait_until="domcontentloaded", timeout=120000)

    wait_chatgpt_post_action_settle(page, multiplier=1.4)
    prepare_chatgpt_page(page)
    return {"url": page.url, "reason": clean_text(reason)}


def conversation_id_from_url(url: str) -> str:
    match = re.search(r"/c/([^/?#]+)", url or "")
    if match:
        return match.group(1)
    path = get_url_path(url)
    if path:
        return sanitize(os.path.basename(path))
    return "conversation"


def ensure_chatgpt_sidebar_visible(page) -> None:
    if get_url_host(page.url) not in CHATGPT_HOSTS:
        return

    prepare_chatgpt_page(page)
    wait_chatgpt_sidebar_settle(page, multiplier=0.6)

    if page.locator('a[href*="/c/"]').count() > 0:
        return

    selectors = [
        'button[aria-label*="sidebar" i]',
        'button[aria-label*="history" i]',
        'button[data-testid*="sidebar"]',
        'button[data-testid*="history"]',
    ]
    for selector in selectors:
        locator = page.locator(selector).first
        try:
            if locator.count() > 0:
                safe_click(locator, timeout=1200, reason=f"sidebar:{selector}")
                wait_chatgpt_sidebar_settle(page)
                if page.locator('a[href*="/c/"]').count() > 0:
                    return
        except Exception:
            continue


def load_all_chatgpt_sidebar_items(page, max_rounds: int = 45) -> None:
    ensure_chatgpt_sidebar_visible(page)
    stable_rounds = 0
    previous_count = 0
    wait_chatgpt_sidebar_settle(page)

    for _ in range(max_rounds):
        current_count = page.locator('a[href*="/c/"]').count()
        if current_count <= previous_count:
            stable_rounds += 1
        else:
            stable_rounds = 0
            previous_count = current_count

        if stable_rounds >= 3:
            break

        page.evaluate(
            """() => {
                const candidates = [...document.querySelectorAll('*')].filter(node => {
                    const style = window.getComputedStyle(node);
                    const hasScrollableArea = node.scrollHeight > node.clientHeight + 80;
                    const overflowY = style.overflowY;
                    const isScrollable = overflowY === 'auto' || overflowY === 'scroll';
                    const hasChatLinks = !!node.querySelector('a[href*="/c/"]');
                    return hasScrollableArea && isScrollable && hasChatLinks;
                });
                const target = candidates.sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
                if (target) {
                    target.scrollTop = target.scrollHeight;
                    return;
                }
                window.scrollTo(0, document.body.scrollHeight);
            }"""
        )
        wait_chatgpt_sidebar_settle(page, multiplier=0.6)


def extract_chatgpt_sidebar_entries(page) -> List[Dict[str, str]]:
    payload = page.evaluate(
        """() => {
            const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
            return [...document.querySelectorAll('a[href*="/c/"]')].map((anchor, index) => {
                const href = anchor.href || '';
                const title = clean(anchor.innerText || anchor.textContent || anchor.getAttribute('aria-label') || anchor.title || '');
                const match = href.match(/\\/c\\/([^/?#]+)/);
                return {
                    href,
                    title,
                    text: title,
                    conversation_id: match ? match[1] : '',
                    index: index + 1
                };
            });
        }"""
    )
    entries: List[Dict[str, str]] = []
    seen = set()
    for item in payload:
        href = item.get("href", "")
        conversation_id = item.get("conversation_id") or conversation_id_from_url(href)
        key = conversation_id or href
        if not href or key in seen:
            continue
        seen.add(key)
        entries.append(
            {
                "href": href,
                "title": clean_text(item.get("title") or ""),
                "conversation_id": conversation_id,
            }
        )
    return entries


def load_chatgpt_sidebar_entries(page, target_url: Optional[str] = None, max_refresh_attempts: int = 2) -> List[Dict[str, str]]:
    entries: List[Dict[str, str]] = []
    for attempt in range(max_refresh_attempts + 1):
        ensure_chatgpt_sidebar_visible(page)
        load_all_chatgpt_sidebar_items(page)
        entries = extract_chatgpt_sidebar_entries(page)
        if entries:
            return entries

        if attempt >= max_refresh_attempts:
            break

        refresh_chatgpt_page(
            page,
            reason=f"sidebar_restore_attempt_{attempt + 1}",
            target_url=target_url or page.url or "https://chatgpt.com/",
        )

    return entries


def find_chatgpt_sidebar_entry(
    entries: List[Dict[str, str]],
    conversation_id: Optional[str] = None,
    title_contains: Optional[str] = None,
) -> Dict[str, str]:
    if conversation_id:
        target = clean_text(conversation_id)
        for entry in entries:
            if clean_text(entry.get("conversation_id") or "") == target:
                return entry
        raise RuntimeError(f"No ChatGPT conversation matched id: {target}")

    if title_contains:
        needle = clean_text(title_contains).lower()
        matches = [entry for entry in entries if needle in clean_text(entry.get("title") or "").lower()]
        if not matches:
            raise RuntimeError(f"No ChatGPT conversation title matched: {title_contains}")
        if len(matches) > 1:
            raise RuntimeError(
                "Multiple ChatGPT conversations matched the requested title fragment: "
                + ", ".join([entry.get("title") or entry.get("conversation_id") or "conversation" for entry in matches[:6]])
            )
        return matches[0]

    raise RuntimeError("Provide a conversation id or title fragment to select an existing ChatGPT conversation.")


def load_full_chatgpt_conversation_history(page, max_rounds: int = 35) -> int:
    stable_rounds = 0
    previous_count = 0

    for _ in range(max_rounds):
        current_count = page.locator('[data-message-author-role], main article').count()
        if current_count <= previous_count:
            stable_rounds += 1
        else:
            stable_rounds = 0
            previous_count = current_count

        if stable_rounds >= 3:
            break

        page.evaluate(
            """() => {
                const candidates = [...document.querySelectorAll('main, section, div')].filter(node => {
                    const style = window.getComputedStyle(node);
                    const overflowY = style.overflowY;
                    const isScrollable = overflowY === 'auto' || overflowY === 'scroll';
                    const hasScrollableArea = node.scrollHeight > node.clientHeight + 80;
                    const hasMessages = !!node.querySelector('[data-message-author-role], article');
                    return isScrollable && hasScrollableArea && hasMessages;
                });
                const target = candidates.sort((a, b) => b.scrollHeight - a.scrollHeight)[0];
                if (target) {
                    target.scrollTop = 0;
                    return;
                }
                window.scrollTo(0, 0);
            }"""
        )
        page.wait_for_timeout(700)

    return previous_count


def dismiss_chatgpt_obstructive_dialogs(page, max_rounds: int = 3) -> List[Dict[str, str]]:
    dismiss_terms = ["got it", "ok", "okay", "close", "dismiss", "continue", "知道了", "关闭", "确认"]
    dismissed: List[Dict[str, str]] = []

    for _ in range(max_rounds):
        dialog_locator = page.locator("[role='dialog']")
        if dialog_locator.count() == 0:
            break

        dismissed_this_round = False
        dialog = dialog_locator.nth(dialog_locator.count() - 1)
        control = find_visible_chatgpt_control(
            dialog,
            include_terms=dismiss_terms,
            selectors=["button", "[role='button']"],
            max_candidates=24,
        )
        if control is not None:
            safe_click(control["locator"], timeout=3000, reason="dismiss_dialog")
            page.wait_for_timeout(800)
            dismissed.append({"label": control.get("label") or "dismiss"})
            dismissed_this_round = True

        if not dismissed_this_round:
            break

    return dismissed


def is_retryable_chatgpt_guard_signal(guard_signal: Optional[Dict[str, str]]) -> bool:
    if not guard_signal:
        return False
    signal = clean_text(guard_signal.get("signal") or "").lower()
    retryable_terms = [
        "too many requests",
        "making requests too quickly",
        "temporarily limited access to your conversations",
    ]
    return any(term in signal for term in retryable_terms)


def recover_chatgpt_retryable_guard(page, guard_signal: Dict[str, str]) -> Dict[str, Any]:
    dismissed = dismiss_chatgpt_obstructive_dialogs(page, max_rounds=2)
    cooldown_seconds = get_chatgpt_guard_cooldown_seconds()
    time.sleep(cooldown_seconds)
    dismiss_chatgpt_obstructive_dialogs(page, max_rounds=1)
    refreshed = refresh_chatgpt_page(page, reason="retryable_guard_refresh", target_url=page.url or "https://chatgpt.com/")
    return {
        "signal": clean_text(guard_signal.get("signal") or ""),
        "dismissed": dismissed,
        "cooldown_seconds": cooldown_seconds,
        "refreshed": refreshed,
    }


def safe_click(locator, timeout: int = 3000, reason: str = "") -> str:
    try:
        try:
            locator.scroll_into_view_if_needed(timeout=min(timeout, 1200))
        except Exception:
            pass
        locator.click(timeout=timeout)
        return "normal"
    except Exception as exc:
        error_text = str(exc).lower()
        if any(token in error_text for token in ["intercepts pointer events", "another element", "subtree intercepts", "not clickable"]):
            try:
                locator.click(timeout=max(timeout, 1000), force=True)
                return "force"
            except Exception:
                pass
            try:
                locator.evaluate("(node) => node.click()")
                return "js"
            except Exception:
                pass
        raise


def inject_chatgpt_reduce_motion_styles(page) -> None:
    try:
        page.evaluate(
            """() => {
                const id = 'codex-chatgpt-low-motion-style';
                if (document.getElementById(id)) {
                    return;
                }
                const style = document.createElement('style');
                style.id = id;
                style.textContent = `
                    html { scroll-behavior: auto !important; }
                    *, *::before, *::after {
                        animation-duration: 0s !important;
                        animation-delay: 0s !important;
                        transition-duration: 0s !important;
                        transition-delay: 0s !important;
                        scroll-behavior: auto !important;
                        caret-color: auto !important;
                    }
                    ::view-transition-old(root), ::view-transition-new(root) {
                        animation: none !important;
                    }
                `;
                document.head.appendChild(style);
            }"""
        )
    except Exception:
        pass


def hide_chatgpt_interfering_overlays(page) -> List[str]:
    try:
        hidden = page.evaluate(
            """() => {
                const labels = [];
                const explicitSelectors = [
                    '[data-keep-ai-memory-tag]',
                    '.keep-ai-memory-float',
                    '#pdfcrowd-convert-main',
                    '[id*="pdfcrowd"]',
                    '[class*="pdfcrowd"]',
                ];
                for (const selector of explicitSelectors) {
                    for (const node of document.querySelectorAll(selector)) {
                        node.style.setProperty('display', 'none', 'important');
                        node.setAttribute('data-codex-hidden-overlay', 'true');
                        labels.push(selector);
                    }
                }

                const textNeedles = [
                    'apply auto hide',
                    'export to pdf',
                    'screenshot reply',
                    'toggle latex mode',
                    'open settings',
                    '自动记忆',
                    'save as pdf'
                ];

                for (const node of document.body.querySelectorAll('*')) {
                    const style = window.getComputedStyle(node);
                    const isFloating = ['fixed', 'sticky'].includes(style.position) || Number(style.zIndex || 0) >= 999;
                    if (!isFloating) {
                        continue;
                    }
                    const text = [node.getAttribute('aria-label') || '', node.getAttribute('title') || '', node.innerText || '']
                        .join(' ')
                        .replace(/\\s+/g, ' ')
                        .trim()
                        .toLowerCase();
                    if (!text) {
                        continue;
                    }
                    if (!textNeedles.some(term => text.includes(term))) {
                        continue;
                    }
                    node.style.setProperty('display', 'none', 'important');
                    node.setAttribute('data-codex-hidden-overlay', 'true');
                    labels.push(text.slice(0, 120));
                }
                return labels;
            }"""
        )
        return [clean_text(item) for item in (hidden or []) if clean_text(item)]
    except Exception:
        return []


def ensure_chatgpt_runtime_resilience(page) -> Dict[str, Any]:
    page_key = id(page)
    if page_key in CHATGPT_RUNTIME_PREPARED_PAGES:
        return {"already_prepared": True}

    result: Dict[str, Any] = {
        "desktop_metrics": False,
        "reduced_motion": False,
        "default_timeouts": False,
    }

    try:
        page.set_default_timeout(15000)
        page.set_default_navigation_timeout(120000)
        result["default_timeouts"] = True
    except Exception:
        pass

    try:
        cdp_session = page.context.new_cdp_session(page)
        try:
            cdp_session.send(
                "Emulation.setDeviceMetricsOverride",
                {
                    "width": CHATGPT_DESKTOP_VIEWPORT["width"],
                    "height": CHATGPT_DESKTOP_VIEWPORT["height"],
                    "deviceScaleFactor": 1,
                    "mobile": False,
                    "screenWidth": CHATGPT_DESKTOP_VIEWPORT["width"],
                    "screenHeight": CHATGPT_DESKTOP_VIEWPORT["height"],
                },
            )
            result["desktop_metrics"] = True
        except Exception:
            pass
        try:
            cdp_session.send("Emulation.setTouchEmulationEnabled", {"enabled": False})
        except Exception:
            pass
    except Exception:
        pass

    try:
        page.emulate_media(reduced_motion="reduce")
        result["reduced_motion"] = True
    except Exception:
        pass

    CHATGPT_RUNTIME_PREPARED_PAGES.add(page_key)
    return result


def prepare_chatgpt_page(page) -> Dict[str, Any]:
    runtime = ensure_chatgpt_runtime_resilience(page)
    inject_chatgpt_reduce_motion_styles(page)
    hidden = hide_chatgpt_interfering_overlays(page)
    dismissed = dismiss_chatgpt_obstructive_dialogs(page, max_rounds=1)
    return {
        "runtime": runtime,
        "hidden_overlays": dedupe_strings(hidden),
        "dismissed_dialogs": dismissed,
    }


def current_chatgpt_input_locator(page):
    prepare_chatgpt_page(page)
    selectors = [
        'textarea',
        'form textarea',
        'div[contenteditable="true"][role="textbox"]',
        'div[contenteditable="true"]',
    ]
    for selector in selectors:
        locator = page.locator(selector)
        if locator.count() > 0:
            for index in range(locator.count()):
                candidate = locator.nth(index)
                try:
                    if candidate.is_visible(timeout=800):
                        return candidate
                except Exception:
                    continue
    raise RuntimeError("Unable to find the ChatGPT prompt input box.")


def click_chatgpt_new_chat(page) -> None:
    current_url = page.url or ""
    if get_url_host(current_url) not in CHATGPT_HOSTS:
        throttle_chatgpt_request("browse", "goto_chatgpt_home_for_new_chat")
        navigate_chatgpt(page, "https://chatgpt.com/", wait_until="domcontentloaded", timeout=120000)
        wait_chatgpt_post_action_settle(page)
        prepare_chatgpt_page(page)

    selectors = [
        'a[href="/"]',
        'button[aria-label*="New chat" i]',
        'button[data-testid*="new-chat"]',
        'a[data-testid*="new-chat"]',
    ]
    for selector in selectors:
        locator = page.locator(selector)
        if locator.count() == 0:
            continue
        try:
            throttle_chatgpt_request("browse", f"new_chat_click:{selector}")
            safe_click(locator.first, timeout=3000, reason=f"new_chat:{selector}")
            wait_chatgpt_post_action_settle(page)
            current_chatgpt_input_locator(page)
            return
        except Exception:
            continue

    throttle_chatgpt_request("browse", "goto_chatgpt_home_fallback")
    navigate_chatgpt(page, "https://chatgpt.com/", wait_until="domcontentloaded", timeout=120000)
    wait_chatgpt_post_action_settle(page, multiplier=1.2)
    prepare_chatgpt_page(page)
    current_chatgpt_input_locator(page)


def open_chatgpt_target(
    page,
    url: Optional[str] = None,
    conversation_id: Optional[str] = None,
    title_contains: Optional[str] = None,
    new_chat: bool = False,
) -> Dict[str, Any]:
    target_url = url or page.url or "https://chatgpt.com/"
    if get_url_host(target_url) not in CHATGPT_HOSTS:
        target_url = "https://chatgpt.com/"

    throttle_chatgpt_request("browse", f"open_target:{target_url}")
    navigate_chatgpt(page, target_url, wait_until="domcontentloaded", timeout=120000)
    wait_chatgpt_post_action_settle(page)

    host = get_url_host(page.url)
    if host not in CHATGPT_HOSTS:
        raise RuntimeError(f"The current page is not ChatGPT: {page.url}")
    if "/auth/" in page.url or "/login" in page.url:
        raise RuntimeError("ChatGPT does not appear to be logged in in this browser profile.")
    prepare_chatgpt_page(page)

    if new_chat:
        click_chatgpt_new_chat(page)
        return {"mode": "new_chat", "url": page.url, "conversation_id": conversation_id_from_url(page.url)}

    if conversation_id or title_contains:
        entries = load_chatgpt_sidebar_entries(page, target_url=target_url)
        chosen = find_chatgpt_sidebar_entry(entries, conversation_id=conversation_id, title_contains=title_contains)
        throttle_chatgpt_request("browse", f"open_existing_chat:{chosen.get('conversation_id') or chosen.get('title') or 'chat'}")
        navigate_chatgpt(page, chosen["href"], wait_until="domcontentloaded", timeout=120000)
        wait_for_chatgpt_conversation(page)
        wait_chatgpt_post_action_settle(page)
        return {
            "mode": "existing_chat",
            "url": page.url,
            "conversation_id": chosen.get("conversation_id") or conversation_id_from_url(page.url),
            "title": chosen.get("title") or "",
        }

    if "/c/" in (page.url or ""):
        wait_for_chatgpt_conversation(page)
        return {"mode": "current_chat", "url": page.url, "conversation_id": conversation_id_from_url(page.url)}

    current_chatgpt_input_locator(page)
    return {"mode": "current_page", "url": page.url, "conversation_id": conversation_id_from_url(page.url)}


def get_chatgpt_control_label(locator) -> str:
    parts: List[str] = []
    for getter in [
        lambda item: item.get_attribute("aria-label") or "",
        lambda item: item.get_attribute("title") or "",
        lambda item: item.inner_text(timeout=800) or "",
    ]:
        try:
            value = getter(locator)
        except Exception:
            value = ""
        if value:
            parts.append(value)
    return clean_text(" ".join(parts))


def find_visible_chatgpt_control(
    root,
    include_terms: List[str],
    selectors: Optional[List[str]] = None,
    exclude_terms: Optional[List[str]] = None,
    max_candidates: int = 40,
) -> Optional[Dict[str, Any]]:
    selectors = selectors or ["button", "[role='button']", "[role='menuitem']"]
    include_lc = [clean_text(term).lower() for term in include_terms if clean_text(term)]
    exclude_lc = [clean_text(term).lower() for term in (exclude_terms or []) if clean_text(term)]

    for selector in selectors:
        locator = root.locator(selector)
        count = min(locator.count(), max_candidates)
        for index in range(count):
            candidate = locator.nth(index)
            try:
                if not candidate.is_visible(timeout=250):
                    continue
            except Exception:
                continue

            label = get_chatgpt_control_label(candidate).lower()
            if not label:
                continue
            if exclude_lc and any(term in label for term in exclude_lc):
                continue
            if any(term in label for term in include_lc):
                return {
                    "selector": selector,
                    "index": index,
                    "label": label,
                    "locator": candidate,
                }
    return None


def open_chatgpt_actions_menu(page) -> Dict[str, Any]:
    prepare_chatgpt_page(page)
    menu_selectors = [
        "main button[aria-haspopup='menu']",
        "header button[aria-haspopup='menu']",
        "button[data-testid*='conversation']",
        "button[data-testid*='action']",
        "button[data-testid*='more']",
        "button[aria-label*='More' i]",
        "button[aria-label*='options' i]",
        "button[aria-label*='menu' i]",
        "button[title*='More' i]",
    ]
    exclude_terms = [
        "account", "profile", "settings", "customize", "memory", "voice", "search", "sidebar",
        "history", "workspace", "upgrade", "share", "temporary", "model", "project",
    ]

    for selector in menu_selectors:
        locator = page.locator(selector)
        count = min(locator.count(), 24)
        for index in range(count):
            candidate = locator.nth(index)
            try:
                if not candidate.is_visible(timeout=250):
                    continue
            except Exception:
                continue

            label = get_chatgpt_control_label(candidate).lower()
            if label and any(term in label for term in exclude_terms):
                continue

            try:
                candidate.scroll_into_view_if_needed(timeout=800)
            except Exception:
                pass

            try:
                safe_click(candidate, timeout=2500, reason=f"actions_menu:{selector}")
                page.wait_for_timeout(700)
            except Exception:
                continue

            delete_control = find_visible_chatgpt_control(
                page,
                include_terms=["delete", "删除"],
                selectors=["[role='menuitem']", "button", "[role='button']"],
                exclude_terms=["delete all", "delete workspace"],
            )
            if delete_control is not None:
                return {
                    "selector": selector,
                    "index": index,
                    "label": label,
                }

            try:
                page.keyboard.press("Escape")
                page.wait_for_timeout(250)
            except Exception:
                pass

    raise RuntimeError("Unable to open a ChatGPT conversation actions menu that exposes Delete.")


def confirm_chatgpt_delete_dialog(page, timeout_seconds: int = 8) -> Dict[str, Any]:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        dialog_locator = page.locator("[role='dialog']")
        dialog_count = dialog_locator.count()
        if dialog_count > 0:
            dialog = dialog_locator.nth(dialog_count - 1)
            try:
                if dialog.is_visible(timeout=250):
                    confirm = find_visible_chatgpt_control(
                        dialog,
                        include_terms=["delete", "删除"],
                        selectors=["button", "[role='button']"],
                        exclude_terms=["delete all", "delete workspace"],
                        max_candidates=24,
                    )
                    if confirm is not None:
                        throttle_chatgpt_request("mutation", "confirm_delete")
                        safe_click(confirm["locator"], timeout=3000, reason="confirm_delete")
                        page.wait_for_timeout(1000)
                        return {"status": "confirmed", "label": confirm["label"]}
            except Exception:
                pass
        time.sleep(0.35)

    return {"status": "not_required"}


def wait_for_chatgpt_deletion(page, expected_conversation_id: str = "", timeout_seconds: int = 20) -> Dict[str, Any]:
    expected_id = clean_text(expected_conversation_id)
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        current_url = page.url or ""
        if not expected_id and "/c/" not in current_url:
            return {"url": current_url, "removed_from_sidebar": None}

        try:
            ensure_chatgpt_sidebar_visible(page)
            entries = extract_chatgpt_sidebar_entries(page)
            if expected_id:
                still_present = any(clean_text(entry.get("conversation_id") or "") == expected_id for entry in entries)
                if not still_present:
                    return {"url": current_url, "removed_from_sidebar": True}
                if expected_id not in current_url:
                    return {"url": current_url, "removed_from_sidebar": False}
        except Exception:
            if expected_id and expected_id not in current_url:
                return {"url": current_url, "removed_from_sidebar": None}

        page.wait_for_timeout(700)

    raise RuntimeError("Timed out waiting for ChatGPT conversation deletion to complete.")


def delete_current_chatgpt_conversation(page, expected_conversation_id: str = "") -> Dict[str, Any]:
    api_error = ""
    if clean_text(expected_conversation_id):
        try:
            api_delete = delete_chatgpt_conversation_via_api(page, expected_conversation_id)
            throttle_chatgpt_request("browse", "post_delete_refresh")
            navigate_chatgpt(page, "https://chatgpt.com/", wait_until="domcontentloaded", timeout=120000)
            page.wait_for_timeout(1200)
            prepare_chatgpt_page(page)
            completion = wait_for_chatgpt_deletion(page, expected_conversation_id=expected_conversation_id, timeout_seconds=20)
            return {
                "strategy": "api_primary",
                "api_delete": api_delete,
                "completion": completion,
            }
        except Exception as exc:
            api_error = f"{type(exc).__name__}: {exc}"

    ui_error = ""
    try:
        delete_control = find_visible_chatgpt_control(
            page,
            include_terms=["delete", "删除"],
            selectors=["[role='menuitem']", "button", "[role='button']"],
            exclude_terms=["delete all", "delete workspace"],
        )
        if delete_control is None:
            menu_info = open_chatgpt_actions_menu(page)
            delete_control = find_visible_chatgpt_control(
                page,
                include_terms=["delete", "删除"],
                selectors=["[role='menuitem']", "button", "[role='button']"],
                exclude_terms=["delete all", "delete workspace"],
            )
        else:
            menu_info = {"selector": "direct", "index": 0, "label": delete_control.get("label") or ""}

        if delete_control is None:
            raise RuntimeError("Unable to find a Delete action for the current ChatGPT conversation.")

        safe_click(delete_control["locator"], timeout=3000, reason="delete_current_chat")
        page.wait_for_timeout(800)
        confirmation = confirm_chatgpt_delete_dialog(page)
        completion = wait_for_chatgpt_deletion(page, expected_conversation_id=expected_conversation_id, timeout_seconds=20)
        return {
            "strategy": "ui",
            "api_error": api_error,
            "menu": menu_info,
            "delete_action": {
                "selector": delete_control.get("selector"),
                "index": delete_control.get("index"),
                "label": delete_control.get("label"),
            },
            "confirmation": confirmation,
            "completion": completion,
        }
    except Exception as exc:
        ui_error = f"{type(exc).__name__}: {exc}"

    raise RuntimeError(ui_error or api_error or "Unable to delete the current ChatGPT conversation.")


def set_chatgpt_prompt_text(page, prompt: str) -> None:
    locator = current_chatgpt_input_locator(page)
    tag_name = (locator.evaluate("(node) => node.tagName.toLowerCase()") or "").lower()
    safe_click(locator, timeout=3000, reason="focus_prompt")
    if tag_name == "textarea":
        locator.fill(prompt, timeout=6000)
        return

    page.keyboard.press("Control+A")
    page.keyboard.press("Backspace")
    page.keyboard.insert_text(prompt)


def upload_chatgpt_files(page, paths: List[str]) -> List[str]:
    if not paths:
        return []

    resolved_paths = []
    for raw_path in paths:
        resolved = str(Path(raw_path).expanduser().resolve())
        if not Path(resolved).exists():
            raise RuntimeError(f"Attachment path not found: {raw_path}")
        resolved_paths.append(resolved)

    file_input = page.locator('input[type="file"]')
    if file_input.count() == 0:
        add_selectors = [
            'button[aria-label*="Add photos" i]',
            'button[aria-label*="Add files" i]',
            'button[aria-label*="Add photos and files" i]',
            'button[data-testid*="add-file"]',
        ]
        for selector in add_selectors:
            locator = page.locator(selector)
            if locator.count() == 0:
                continue
            try:
                safe_click(locator.first, timeout=2000, reason=f"open_upload:{selector}")
                page.wait_for_timeout(700)
                break
            except Exception:
                continue
        file_input = page.locator('input[type="file"]')

    if file_input.count() == 0:
        raise RuntimeError("Unable to find ChatGPT file upload input.")

    file_input.first.set_input_files(resolved_paths)
    page.wait_for_timeout(2000)
    return resolved_paths


def wait_for_chatgpt_send_ready(locator, timeout_seconds: float = 2.5) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            if not locator.is_visible(timeout=250):
                time.sleep(0.1)
                continue

            disabled_attr = clean_text(locator.get_attribute("disabled") or "").lower()
            aria_disabled = clean_text(locator.get_attribute("aria-disabled") or "").lower()
            if not disabled_attr and aria_disabled not in {"true", "1"}:
                return
        except Exception:
            pass

        time.sleep(0.1)


def chatgpt_send_prompt(page) -> None:
    button_selectors = [
        'button[aria-label*="Send prompt" i]',
        'button[aria-label*="Send message" i]',
        'button[data-testid*="send"]',
    ]
    for selector in button_selectors:
        locator = page.locator(selector)
        if locator.count() == 0:
            continue
        try:
            wait_for_chatgpt_send_ready(locator.first)
            safe_click(locator.first, timeout=2500, reason=f"send_prompt:{selector}")
            return
        except Exception:
            continue

    page.keyboard.press("Enter")


def latest_assistant_message(conversation: Dict[str, Any]) -> Dict[str, Any]:
    assistant_messages = [message for message in conversation.get("messages", []) if clean_text(message.get("role") or "").lower() == "assistant"]
    if assistant_messages:
        return assistant_messages[-1]
    if conversation.get("messages"):
        return conversation["messages"][-1]
    return {"index": 0, "role": "assistant", "text": "", "code_blocks": []}


def wait_for_chatgpt_answer(
    page,
    before_conversation: Dict[str, Any],
    timeout_seconds: int = 300,
    max_total_seconds: int = 0,
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    started_at = time.time()
    last_progress_at = started_at
    before_last = latest_assistant_message(before_conversation)
    before_text = before_last.get("text") or ""
    before_assistant_count = len(
        [message for message in before_conversation.get("messages", []) if clean_text(message.get("role") or "").lower() == "assistant"]
    )
    stable_rounds = 0
    answer_started = False
    previous_text = before_text
    previous_count = before_assistant_count
    previous_conversation_id = conversation_id_from_url(before_conversation.get("url") or page.url or "")
    retryable_guard_count = 0

    while True:
        now = time.time()
        if max_total_seconds > 0 and (now - started_at) > max_total_seconds:
            raise RuntimeError(
                f"Timed out after {max_total_seconds} seconds overall while waiting for ChatGPT to finish responding."
            )

        dismiss_chatgpt_obstructive_dialogs(page, max_rounds=1)
        guard_signal = detect_chatgpt_guard_signal(page)
        if guard_signal:
            if is_retryable_chatgpt_guard_signal(guard_signal) and retryable_guard_count < 3:
                recover_chatgpt_retryable_guard(page, guard_signal)
                retryable_guard_count += 1
                continue
            raise RuntimeError(f"ChatGPT guard detected while waiting for a response: {guard_signal['signal']}")

        conversation = extract_chatgpt_conversation_payload(page)
        last_assistant = latest_assistant_message(conversation)
        assistant_messages = [
            message for message in conversation.get("messages", []) if clean_text(message.get("role") or "").lower() == "assistant"
        ]
        current_count = len(assistant_messages)
        current_text = last_assistant.get("text") or ""
        current_conversation_id = conversation_id_from_url(page.url or "")
        if current_count > before_assistant_count or current_text != before_text:
            answer_started = True

        stop_visible = False
        for selector in ['button[aria-label*="Stop" i]', 'button:has-text("Stop generating")', 'button:has-text("Stop")']:
            locator = page.locator(selector)
            try:
                if locator.count() > 0 and locator.first.is_visible(timeout=300):
                    stop_visible = True
                    break
            except Exception:
                continue

        progress_detected = False
        if current_count > previous_count:
            progress_detected = True
        if current_text != previous_text:
            progress_detected = True
        if current_conversation_id and current_conversation_id != previous_conversation_id:
            progress_detected = True

        if progress_detected:
            last_progress_at = now

        if answer_started:
            if current_text and current_text == previous_text and not stop_visible:
                stable_rounds += 1
            else:
                stable_rounds = 0

            if stable_rounds >= 2 and current_text and not stop_visible:
                return conversation, last_assistant
        else:
            if (now - last_progress_at) > timeout_seconds:
                raise RuntimeError(
                    f"Timed out waiting for ChatGPT to start responding after {timeout_seconds} seconds."
                )

        if answer_started:
            effective_idle_limit = timeout_seconds
            if stop_visible:
                effective_idle_limit = max(timeout_seconds * 6, timeout_seconds + 300)

            if (now - last_progress_at) > effective_idle_limit:
                if stop_visible:
                    raise RuntimeError(
                        "ChatGPT appears to be stuck while generating. "
                        f"No new answer progress was detected for {int(now - last_progress_at)} seconds."
                    )
                raise RuntimeError(
                    f"Timed out waiting for ChatGPT response activity after {timeout_seconds} seconds of inactivity."
                )

        previous_text = current_text
        previous_count = current_count
        previous_conversation_id = current_conversation_id or previous_conversation_id
        time.sleep(get_chatgpt_poll_interval_seconds())


def build_requests_session_from_context(context, page) -> requests.Session:
    session = requests.Session()
    try:
        cookies = context.cookies()
    except Exception:
        cookies = []
    for cookie in cookies:
        session.cookies.set(
            cookie.get("name"),
            cookie.get("value"),
            domain=cookie.get("domain"),
            path=cookie.get("path") or "/",
        )
    try:
        user_agent = page.evaluate("() => navigator.userAgent")
    except Exception:
        user_agent = ""
    if user_agent:
        session.headers.update({"User-Agent": user_agent})
    return session


def is_probable_chatgpt_file_link(href: str, text: str = "", download_name: str = "") -> bool:
    href_lc = (href or "").lower()
    path = get_url_path(href_lc)
    if is_probable_file_link(href, text or download_name):
        return True
    if "/files/" in path or "/backend-api/" in path or "download=true" in href_lc:
        return True
    if download_name:
        _, ext = os.path.splitext(download_name.lower())
        if ext in COMMON_FILE_EXTENSIONS:
            return True
    return False


def collect_chatgpt_message_file_targets(page) -> Dict[str, Any]:
    assistant_locator = page.locator('[data-message-author-role="assistant"]').last
    anchors = []
    try:
        anchor_locator = assistant_locator.locator('a[href]')
        for index in range(anchor_locator.count()):
            anchor = anchor_locator.nth(index)
            href = anchor.get_attribute("href") or ""
            text = clean_text(anchor.inner_text(timeout=1000) if anchor.count() >= 0 else "")
            download_name = clean_text(anchor.get_attribute("download") or "")
            if not href:
                continue
            if href.startswith("blob:"):
                continue
            if not is_probable_chatgpt_file_link(href, text=text, download_name=download_name):
                continue
            anchors.append(
                {
                    "href": href,
                    "text": text,
                    "download_name": download_name,
                }
            )
    except Exception:
        anchors = []

    buttons = []
    try:
        button_locator = assistant_locator.locator('button')
        for index in range(button_locator.count()):
            button = button_locator.nth(index)
            label = clean_text(
                (button.get_attribute("aria-label") or "")
                + " "
                + (button.inner_text(timeout=1000) or "")
                + " "
                + (button.get_attribute("title") or "")
            )
            if "download" not in label.lower():
                continue
            buttons.append({"index": index, "label": label or f"download_{index + 1}"})
    except Exception:
        buttons = []

    return {"anchors": dedupe_dicts(anchors), "buttons": buttons}


def get_chatgpt_access_token(page) -> str:
    token = page.evaluate(
        """async () => {
            const response = await fetch('/api/auth/session', { credentials: 'include' });
            if (!response.ok) {
                return '';
            }
            const payload = await response.json();
            return payload.accessToken || '';
        }"""
    )
    token = clean_text(token)
    if not token:
        raise RuntimeError("Unable to obtain a ChatGPT access token from the current logged-in session.")
    return token


def normalize_chatgpt_message_text(value: str) -> str:
    text = (value or "").replace("\r", "")
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def flatten_chatgpt_content_fragment(fragment: Any) -> List[str]:
    if fragment is None:
        return []
    if isinstance(fragment, str):
        text = normalize_chatgpt_message_text(fragment)
        return [text] if text else []
    if isinstance(fragment, list):
        results: List[str] = []
        for item in fragment:
            results.extend(flatten_chatgpt_content_fragment(item))
        return results
    if isinstance(fragment, dict):
        results: List[str] = []
        for key in ["text", "parts", "content", "value", "result", "caption", "title"]:
            if key in fragment:
                results.extend(flatten_chatgpt_content_fragment(fragment.get(key)))
        return results
    text = normalize_chatgpt_message_text(str(fragment))
    return [text] if text else []


def extract_chatgpt_text_from_message(message: Dict[str, Any]) -> str:
    content = message.get("content") or {}
    fragments = flatten_chatgpt_content_fragment(content.get("parts") if isinstance(content, dict) else content)
    text = "\n\n".join([item for item in fragments if item])
    return normalize_chatgpt_message_text(text)


def fetch_chatgpt_conversation_api_payload(page, conversation_id: str) -> Dict[str, Any]:
    if not clean_text(conversation_id) or clean_text(conversation_id) == "untitled":
        raise RuntimeError("A persisted ChatGPT conversation id is required for API conversation fetch.")

    throttle_chatgpt_request("browse", f"api_fetch:{conversation_id}")
    token = get_chatgpt_access_token(page)
    result = page.evaluate(
        """async ({conversationId, token}) => {
            const response = await fetch(`https://chatgpt.com/backend-api/conversation/${conversationId}`, {
                method: 'GET',
                credentials: 'include',
                headers: {
                    'Accept': 'application/json, text/plain, */*',
                    'Authorization': `Bearer ${token}`,
                },
            });
            const text = await response.text();
            if (!response.ok) {
                return {
                    status: response.status,
                    ok: false,
                    text: text.slice(0, 1000),
                };
            }
            return {
                status: response.status,
                ok: true,
                json: JSON.parse(text),
            };
        }""",
        {"conversationId": conversation_id, "token": token},
    )
    if not result.get("ok"):
        raise RuntimeError(
            f"ChatGPT API conversation fetch failed with status {result.get('status')}: {(result.get('text') or '')[:240]}"
        )
    return result.get("json") or {}


def build_chatgpt_conversation_from_api_payload(raw_payload: Dict[str, Any], conversation_id: str, fallback_url: str = "") -> Dict[str, Any]:
    mapping = raw_payload.get("mapping") or {}
    current_node = raw_payload.get("current_node")
    if not current_node:
        leaf_candidates = []
        for node_id, node in mapping.items():
            if not (node or {}).get("children"):
                leaf_candidates.append(node_id)
        if leaf_candidates:
            current_node = leaf_candidates[-1]

    ordered_ids: List[str] = []
    seen = set()
    node_id = current_node
    while node_id and node_id not in seen:
        seen.add(node_id)
        ordered_ids.append(node_id)
        node = mapping.get(node_id) or {}
        node_id = node.get("parent")
    ordered_ids.reverse()

    messages: List[Dict[str, Any]] = []
    for ordinal, node_id in enumerate(ordered_ids, start=1):
        node = mapping.get(node_id) or {}
        message = node.get("message") or {}
        metadata = message.get("metadata") or {}
        role = clean_text(((message.get("author") or {}).get("role")) or "")
        if metadata.get("is_visually_hidden_from_conversation"):
            continue
        if role in {"", "system"}:
            continue
        text = extract_chatgpt_text_from_message(message)
        if not text:
            continue
        messages.append(
            {
                "index": len(messages) + 1,
                "role": role,
                "text": text,
                "code_blocks": [],
            }
        )

    title = clean_text(raw_payload.get("title") or "") or conversation_id or "conversation"
    url = fallback_url or (f"https://chatgpt.com/c/{conversation_id}" if conversation_id else "")
    return {
        "title": title,
        "url": url,
        "message_count": len(messages),
        "messages": messages,
        "conversation_id": conversation_id,
        "capture_source": "api",
    }


def delete_chatgpt_conversation_via_api(page, conversation_id: str) -> Dict[str, Any]:
    if not clean_text(conversation_id):
        raise RuntimeError("A conversation id is required for the API delete fallback.")

    throttle_chatgpt_request("mutation", f"api_delete:{conversation_id}")
    token = get_chatgpt_access_token(page)
    result = page.evaluate(
        """async ({conversationId, token}) => {
            const response = await fetch(`https://chatgpt.com/backend-api/conversation/${conversationId}`, {
                method: 'PATCH',
                credentials: 'include',
                headers: {
                    'Accept': 'application/json, text/plain, */*',
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`,
                },
                body: JSON.stringify({ is_visible: false }),
            });
            const text = await response.text();
            return {
                status: response.status,
                text: text.slice(0, 1000),
            };
        }""",
        {"conversationId": conversation_id, "token": token},
    )
    status = int(result.get("status") or 0)
    response_text = result.get("text") or ""
    if status not in {200, 404}:
        raise RuntimeError(f"ChatGPT API delete fallback failed with status {status}: {response_text[:240]}")
    return {
        "status": status,
        "response_excerpt": response_text[:240],
    }


def download_chatgpt_message_files(page, destination_dir: Path, base_name: str) -> List[Dict[str, Any]]:
    destination_dir.mkdir(parents=True, exist_ok=True)
    context = page.context
    session = build_requests_session_from_context(context, page)
    targets = collect_chatgpt_message_file_targets(page)
    results: List[Dict[str, Any]] = []

    for index, anchor in enumerate(targets.get("anchors", []), start=1):
        href = anchor.get("href") or ""
        if not href.startswith(("http://", "https://")):
            continue
        fallback_name = anchor.get("download_name") or anchor.get("text") or f"{base_name}_{index}"
        target_path = build_output_path(str(destination_dir), None, fallback_name, fallback_name)
        try:
            ensure_parent(target_path)
            with session.get(href, stream=True, timeout=180) as response:
                response.raise_for_status()
                output_name = filename_from_response(href, dict(response.headers), fallback_name)
                target_path = build_output_path(str(destination_dir), None, output_name, output_name)
                ensure_parent(target_path)
                with target_path.open("wb") as handle:
                    for chunk in response.iter_content(chunk_size=1024 * 1024):
                        if chunk:
                            handle.write(chunk)
            results.append({"status": "downloaded", "path": str(target_path), "url": href})
        except Exception as exc:
            results.append({"status": "error", "url": href, "error": f"{type(exc).__name__}: {exc}"})

    try:
        assistant_locator = page.locator('[data-message-author-role="assistant"]').last
        button_locator = assistant_locator.locator('button')
        for button_target in targets.get("buttons", []):
            button = button_locator.nth(int(button_target.get("index", 0)))
            label = button_target.get("label") or "download"
            target_path = build_output_path(str(destination_dir), None, sanitize(label), sanitize(label))
            try:
                with page.expect_download(timeout=30000) as download_info:
                    safe_click(button, timeout=3000, reason="assistant_file_download")
                download = download_info.value
                suggested = sanitize(download.suggested_filename or target_path.name)
                target_path = build_output_path(str(destination_dir), None, suggested, suggested)
                download.save_as(str(target_path))
                results.append({"status": "downloaded", "path": str(target_path), "label": label})
            except Exception as exc:
                results.append({"status": "error", "label": label, "error": f"{type(exc).__name__}: {exc}"})
    except Exception:
        pass

    return results


def wait_for_chatgpt_conversation(page) -> None:
    prepare_chatgpt_page(page)
    selectors = ['[data-message-author-role]', 'main article', 'main']
    for selector in selectors:
        try:
            page.wait_for_selector(selector, timeout=12000)
            break
        except Exception:
            continue
    page.wait_for_timeout(1200)


def extract_chatgpt_conversation_payload(page) -> Dict[str, Any]:
    payload = page.evaluate(
        """() => {
            const clean = value => (value || '')
                .replace(/\\r/g, '')
                .replace(/[ \\t]+\\n/g, '\\n')
                .replace(/\\n{3,}/g, '\\n\\n')
                .trim();

            const titleFromDoc = clean((document.title || '').replace(/\\s*\\|\\s*ChatGPT.*$/i, ''));
            const heading = document.querySelector('main h1');
            const title = clean((heading && heading.innerText) || titleFromDoc || 'conversation');

            let nodes = [...document.querySelectorAll('[data-message-author-role]')];
            let messages = nodes.map((node, index) => {
                const role = clean(node.getAttribute('data-message-author-role') || '');
                const text = clean(node.innerText || node.textContent || '');
                const codeBlocks = [...node.querySelectorAll('pre code')].map(code => clean(code.innerText || code.textContent || '')).filter(Boolean);
                return {
                    index: index + 1,
                    role: role || (index % 2 === 0 ? 'user' : 'assistant'),
                    text,
                    code_blocks: codeBlocks
                };
            }).filter(message => message.text);

            if (!messages.length) {
                const articles = [...document.querySelectorAll('main article')];
                messages = articles.map((article, index) => ({
                    index: index + 1,
                    role: index % 2 === 0 ? 'user' : 'assistant',
                    text: clean(article.innerText || article.textContent || ''),
                    code_blocks: [...article.querySelectorAll('pre code')].map(code => clean(code.innerText || code.textContent || '')).filter(Boolean)
                })).filter(message => message.text);
            }

            return {
                title,
                url: location.href,
                message_count: messages.length,
                messages
            };
        }"""
    )
    payload["title"] = clean_text(payload.get("title") or "")
    payload["url"] = payload.get("url") or page.url
    payload["capture_source"] = "dom"
    return payload


def classify_chatgpt_topic_match(
    conversation: Dict[str, Any],
    keywords: Optional[List[str]] = None,
    topic_label: str = "topic",
) -> Dict[str, Any]:
    keyword_list = normalize_keyword_list(keywords)
    parts = [conversation.get("title", "")]
    for message in conversation.get("messages", [])[:12]:
        text = message.get("text", "")
        if text:
            parts.append(text[:2400])
    haystack = "\n".join(parts)
    haystack_lc = haystack.lower()

    matched = []
    for keyword in keyword_list:
        if keyword.lower() in haystack_lc:
            matched.append(keyword)

    if re.search(r"\b[A-Z]{4}\d{4}\b", haystack):
        matched.append("course_code")

    matched = dedupe_strings(matched)
    topic_match = bool(matched)
    return {
        "topic_label": clean_text(topic_label) or "topic",
        "topic_match": topic_match,
        "matched_keywords": matched,
        "keyword_count": len(matched),
        "learning_related": topic_match,
    }


def chatgpt_conversation_markdown(conversation: Dict[str, Any]) -> str:
    lines = [f"# {conversation.get('title') or 'conversation'}", ""]
    lines.append(f"- URL: {conversation.get('url') or ''}")
    lines.append(f"- Topic label: {conversation.get('topic_label') or 'topic'}")
    lines.append(f"- Topic matched: {'yes' if conversation.get('topic_match') else 'no'}")
    lines.append(f"- Matched keywords: {', '.join(conversation.get('matched_keywords') or [])}")
    lines.append("")

    for message in conversation.get("messages", []):
        role = clean_text(message.get("role") or "message").title()
        lines.append(f"## {role}")
        lines.append("")
        lines.append(message.get("text") or "")
        lines.append("")

    return "\n".join(lines).strip() + "\n"


def save_chatgpt_conversation_bundle(page, destination_dir: Path, conversation: Dict[str, Any], ordinal: int) -> Dict[str, str]:
    bundle_name = sanitize(f"{ordinal:03d}_{conversation.get('title') or conversation.get('conversation_id') or 'conversation'}")
    bundle_dir = destination_dir / bundle_name
    bundle_dir.mkdir(parents=True, exist_ok=True)

    html_path = bundle_dir / "conversation.html"
    json_path = bundle_dir / "conversation.json"
    md_path = bundle_dir / "conversation.md"

    save_html(page, html_path)
    write_text(json_path, json.dumps(conversation, indent=2, ensure_ascii=False))
    write_text(md_path, chatgpt_conversation_markdown(conversation))

    return {
        "bundle_dir": str(bundle_dir),
        "html_path": str(html_path),
        "json_path": str(json_path),
        "markdown_path": str(md_path),
    }


def write_chatgpt_export_manifest(destination_dir: Path, topic_label: str, manifest: Dict[str, Any]) -> Path:
    topic_slug = sanitize(topic_label or "topic", max_len=48).replace(" ", "_")
    manifest_path = destination_dir / f"chatgpt_{topic_slug}_manifest.json"
    write_text(manifest_path, json.dumps(manifest, indent=2, ensure_ascii=False))
    return manifest_path


def export_single_chatgpt_conversation(
    page,
    destination_dir: Path,
    ordinal: int = 1,
    bundle_prefix: str = "conversation",
) -> Dict[str, Any]:
    conversation_id = conversation_id_from_url(page.url)
    conversation = None
    api_error = ""
    if conversation_id and conversation_id != "untitled":
        try:
            raw_payload = fetch_chatgpt_conversation_api_payload(page, conversation_id)
            conversation = build_chatgpt_conversation_from_api_payload(raw_payload, conversation_id, fallback_url=page.url)
        except Exception as exc:
            api_error = f"{type(exc).__name__}: {exc}"

    if conversation is None:
        load_full_chatgpt_conversation_history(page)
        conversation = extract_chatgpt_conversation_payload(page)

    conversation["conversation_id"] = conversation_id
    if api_error:
        conversation["api_error"] = api_error
    if not conversation.get("title"):
        conversation["title"] = conversation["conversation_id"] or "conversation"

    export_root = destination_dir / bundle_prefix
    export_root.mkdir(parents=True, exist_ok=True)
    saved_paths = save_chatgpt_conversation_bundle(page, export_root, conversation, ordinal)
    return {
        "conversation": conversation,
        "saved_paths": saved_paths,
        "root_dir": str(export_root),
    }


def cmd_chatgpt_list(args) -> Dict[str, Any]:
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            open_chatgpt_target(page, url=args.url)
            entries = load_chatgpt_sidebar_entries(page, target_url=args.url or page.url or "https://chatgpt.com/")
            if args.title_contains:
                needle = clean_text(args.title_contains).lower()
                entries = [entry for entry in entries if needle in clean_text(entry.get("title") or "").lower()]
            if args.limit:
                entries = entries[: args.limit]
            return {
                "status": "ok",
                "count": len(entries),
                "items": entries,
            }
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_chatgpt_open(args) -> Dict[str, Any]:
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            selection = open_chatgpt_target(
                page,
                url=args.url,
                conversation_id=args.conversation_id,
                title_contains=args.title_contains,
                new_chat=args.new_chat,
            )
            result: Dict[str, Any] = {
                "status": "ok",
                "selection": selection,
                "url": page.url,
            }
            if args.export_dir:
                export_dir = ensure_existing_directory(args.export_dir, "ChatGPT export directory")
                exported = export_single_chatgpt_conversation(page, export_dir, bundle_prefix="selected_conversation")
                result["export"] = exported
            return result
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_chatgpt_save(args) -> Dict[str, Any]:
    export_dir = ensure_existing_directory(args.destination_dir, "ChatGPT destination directory")
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            open_chatgpt_target(
                page,
                url=args.url,
                conversation_id=args.conversation_id,
                title_contains=args.title_contains,
                new_chat=args.new_chat,
            )
            exported = export_single_chatgpt_conversation(page, export_dir)
            return {
                "status": "ok",
                "url": page.url,
                "conversation_id": exported["conversation"].get("conversation_id") or conversation_id_from_url(page.url),
                "title": exported["conversation"].get("title") or "",
                "message_count": exported["conversation"].get("message_count") or len(exported["conversation"].get("messages", [])),
                "saved_paths": exported["saved_paths"],
            }
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_chatgpt_delete(args) -> Dict[str, Any]:
    if not args.confirm_delete:
        raise RuntimeError("chatgpt-delete is destructive. Re-run with --confirm-delete after verifying the target.")
    if not args.current_chat and not args.conversation_id and not args.title_contains:
        raise RuntimeError("Provide --conversation-id, --title-contains, or --current-chat.")

    export_dir = ensure_existing_directory(args.export_dir, "ChatGPT export directory") if args.export_dir else None
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            selection = open_chatgpt_target(
                page,
                url=None if args.current_chat else args.url,
                conversation_id=args.conversation_id,
                title_contains=args.title_contains,
                new_chat=False,
            )
            if args.current_chat and "/c/" not in (page.url or ""):
                raise RuntimeError(
                    "Current page is not an existing ChatGPT conversation. Open the target chat first or provide --conversation-id/--title-contains."
                )

            conversation = extract_chatgpt_conversation_payload(page)
            conversation_id = conversation_id_from_url(page.url)
            title = conversation.get("title") or selection.get("title") or conversation_id

            exported = None
            if export_dir is not None:
                exported = export_single_chatgpt_conversation(page, export_dir, bundle_prefix="deleted_conversation_backup")

            deletion = delete_current_chatgpt_conversation(page, expected_conversation_id=conversation_id)
            return {
                "status": "ok",
                "selection": selection,
                "conversation_id": conversation_id,
                "title": title,
                "export": exported,
                "deletion": deletion,
                "url_after_delete": page.url,
            }
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_chatgpt_ask(args) -> Dict[str, Any]:
    destination_dir = ensure_existing_directory(args.destination_dir, "ChatGPT destination directory")
    run_dir = destination_dir / sanitize(args.result_name or f"chatgpt_ask_{time.strftime('%Y%m%d_%H%M%S')}")
    run_dir.mkdir(parents=True, exist_ok=True)
    prompt_text = resolve_chatgpt_prompt_text(args)
    if not clean_text(prompt_text):
        raise RuntimeError("Prompt text is empty after resolving the requested prompt source.")
    prompt_text_path = run_dir / "user_prompt.txt"
    write_text(prompt_text_path, prompt_text)

    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            selection = open_chatgpt_target(
                page,
                url=args.url,
                conversation_id=args.conversation_id,
                title_contains=args.title_contains,
                new_chat=args.new_chat,
            )

            history_before = None
            if args.export_history_before:
                history_before = export_single_chatgpt_conversation(page, run_dir, bundle_prefix="history_before")

            before_conversation = extract_chatgpt_conversation_payload(page)
            uploaded_paths = upload_chatgpt_files(page, args.attachment or [])
            set_chatgpt_prompt_text(page, prompt_text)
            chatgpt_send_prompt(page)
            after_conversation, assistant_message = wait_for_chatgpt_answer(
                page,
                before_conversation,
                timeout_seconds=args.timeout,
                max_total_seconds=args.max_total_seconds,
            )
            after_conversation["conversation_id"] = conversation_id_from_url(page.url)
            if not after_conversation.get("title"):
                after_conversation["title"] = after_conversation["conversation_id"] or "conversation"

            history_after = export_single_chatgpt_conversation(page, run_dir, bundle_prefix="history_after")
            answer_text = assistant_message.get("text") or ""
            answer_text_path = run_dir / "assistant_answer.txt"
            write_text(answer_text_path, answer_text)
            prompt_preview, prompt_truncated = compact_text_for_cli(prompt_text)
            answer_preview, answer_truncated = compact_text_for_cli(answer_text)

            files_dir = run_dir / "assistant_files"
            downloaded_files = download_chatgpt_message_files(
                page,
                files_dir,
                base_name=sanitize(after_conversation.get("title") or "assistant_file"),
            )

            result = {
                "status": "ok",
                "selection": selection,
                "url": page.url,
                "conversation_id": after_conversation.get("conversation_id") or conversation_id_from_url(page.url),
                "title": after_conversation.get("title") or "",
                "prompt": prompt_preview,
                "prompt_path": str(prompt_text_path),
                "prompt_char_count": len(prompt_text),
                "prompt_truncated": prompt_truncated,
                "uploaded_paths": uploaded_paths,
                "assistant_text": answer_preview,
                "assistant_text_path": str(answer_text_path),
                "assistant_text_char_count": len(answer_text),
                "assistant_text_truncated": answer_truncated,
                "downloaded_files": downloaded_files,
                "history_before": history_before,
                "history_after": history_after,
                "output_dir": str(run_dir),
                "stall_timeout_seconds": args.timeout,
                "max_total_seconds": args.max_total_seconds,
            }
            result_path = run_dir / "result.json"
            write_text(result_path, json.dumps(result, indent=2, ensure_ascii=False))
            result["result_path"] = str(result_path)
            return result
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_chatgpt_export(args) -> Dict[str, Any]:
    destination_dir = ensure_existing_directory(args.destination_dir, "ChatGPT destination directory")
    fallback_keywords = DEFAULT_STUDY_KEYWORDS if args.default_study_keywords else None
    keywords = normalize_keyword_list(args.keyword, fallback_keywords=fallback_keywords)
    topic_label = clean_text(args.topic_label or "")
    if not topic_label:
        topic_label = "learning" if args.default_study_keywords else "topic"
    if not keywords and not args.save_all:
        raise RuntimeError("Provide --keyword, use --default-study-keywords, or pass --save-all.")
    risk_report = build_chatgpt_risk_report(
        keywords=keywords,
        topic_label=topic_label,
        save_all=args.save_all,
        use_study_keywords=args.default_study_keywords,
        explicit_limit=args.limit,
    )
    warnings = list(risk_report["warnings"])
    effective_limit = risk_report["effective_limit"]

    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            url = args.url or page.url or "https://chatgpt.com/"
            navigate_chatgpt(page, url, wait_until="domcontentloaded", timeout=120000)
            page.wait_for_timeout(1800)

            host = get_url_host(page.url)
            if host not in CHATGPT_HOSTS:
                raise RuntimeError(f"The current page is not ChatGPT: {page.url}")
            if "/auth/" in page.url or "/login" in page.url:
                raise RuntimeError("ChatGPT does not appear to be logged in in this browser profile.")
            initial_guard = detect_chatgpt_guard_signal(page)
            if initial_guard:
                raise RuntimeError(f"ChatGPT appears to be temporarily guarded or rate-limited: {initial_guard['signal']}")

            entries = load_chatgpt_sidebar_entries(page, target_url=url)
            if not entries:
                raise RuntimeError("No ChatGPT conversations were found in the sidebar. Make sure history is enabled and the session is logged in.")

            if effective_limit:
                entries = entries[: effective_limit]

            manifest_items: List[Dict[str, Any]] = []
            matched_count = 0
            saved_count = 0
            processed_count = 0
            consecutive_errors = 0
            stop_reason = ""
            status = "ok"

            manifest: Dict[str, Any] = {
                "status": status,
                "root_dir": str(destination_dir),
                "count": len(entries),
                "processed_count": processed_count,
                "matched_count": matched_count,
                "saved_count": saved_count,
                "topic_label": topic_label,
                "keywords": keywords,
                "risk_level": risk_report["risk_level"],
                "effective_limit": effective_limit,
                "auto_limited": risk_report["auto_limited"],
                "warnings": warnings,
                "stop_reason": stop_reason,
                "items": manifest_items,
            }
            manifest_path = write_chatgpt_export_manifest(destination_dir, topic_label, manifest)

            for index, entry in enumerate(entries, start=1):
                try:
                    throttle_chatgpt_request("browse", f"export_open:{entry.get('conversation_id') or entry.get('title') or index}")
                    navigate_chatgpt(page, entry["href"], wait_until="domcontentloaded", timeout=120000)
                    wait_for_chatgpt_conversation(page)
                    guard_signal = detect_chatgpt_guard_signal(page)
                    if guard_signal:
                        stop_reason = f"guard_detected: {guard_signal['signal']}"
                        warnings.append(
                            "ChatGPT showed a temporary guard or rate-limit signal. "
                            "The export stopped early to avoid stressing the session."
                        )
                        status = "stopped_guard"
                        break

                    conversation = extract_chatgpt_conversation_payload(page)
                    conversation["conversation_id"] = entry.get("conversation_id") or conversation_id_from_url(page.url)
                    if not conversation.get("title"):
                        conversation["title"] = entry.get("title") or conversation["conversation_id"]

                    classification = classify_chatgpt_topic_match(conversation, keywords, topic_label=topic_label)
                    conversation.update(classification)

                    saved_paths = {}
                    item_status = "scanned"
                    if conversation["topic_match"] or args.save_all:
                        saved_paths = save_chatgpt_conversation_bundle(page, destination_dir, conversation, index)
                        saved_count += 1
                        item_status = "saved"
                    if conversation["topic_match"]:
                        matched_count += 1

                    manifest_items.append(
                        {
                            "index": index,
                            "status": item_status,
                            "title": conversation.get("title") or "",
                            "url": conversation.get("url") or entry["href"],
                            "conversation_id": conversation.get("conversation_id") or "",
                            "message_count": conversation.get("message_count") or len(conversation.get("messages", [])),
                            "topic_label": conversation.get("topic_label") or topic_label,
                            "topic_match": conversation.get("topic_match", False),
                            "learning_related": conversation.get("learning_related", False),
                            "matched_keywords": conversation.get("matched_keywords", []),
                            "saved_paths": saved_paths,
                        }
                    )
                    processed_count += 1
                    consecutive_errors = 0
                except Exception as exc:
                    processed_count += 1
                    consecutive_errors += 1
                    error_message = f"{type(exc).__name__}: {exc}"
                    manifest_items.append(
                        {
                            "index": index,
                            "status": "error",
                            "title": entry.get("title") or "",
                            "url": entry.get("href") or "",
                            "conversation_id": entry.get("conversation_id") or "",
                            "error": error_message,
                        }
                    )

                    error_lc = error_message.lower()
                    if any(phrase in error_lc for phrase in CHATGPT_GUARD_PHRASES):
                        stop_reason = f"guard_error: {error_message}"
                        warnings.append(
                            "A guard-like error appeared while opening conversations. "
                            "The export stopped early to reduce the chance of temporary closure."
                        )
                        status = "stopped_guard"
                        break
                    if consecutive_errors >= 2:
                        stop_reason = f"too_many_consecutive_errors: {error_message}"
                        warnings.append(
                            "The exporter hit multiple consecutive errors and stopped early instead of continuing to retry."
                        )
                        status = "partial"
                        break
                finally:
                    manifest["status"] = status
                    manifest["processed_count"] = processed_count
                    manifest["matched_count"] = matched_count
                    manifest["saved_count"] = saved_count
                    manifest["warnings"] = dedupe_strings(warnings)
                    manifest["stop_reason"] = stop_reason
                    manifest["items"] = manifest_items
                    manifest_path = write_chatgpt_export_manifest(destination_dir, topic_label, manifest)

                if stop_reason:
                    break
                if index < len(entries):
                    time.sleep(chatgpt_iteration_delay_seconds(risk_report["risk_level"]))

            if stop_reason and status == "ok":
                status = "partial"
                manifest["status"] = status
                manifest["stop_reason"] = stop_reason
                manifest["warnings"] = dedupe_strings(warnings)
                manifest_path = write_chatgpt_export_manifest(destination_dir, topic_label, manifest)

            manifest["manifest_path"] = str(manifest_path)
            return manifest
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def save_html(page, out_path: Path) -> Path:
    html = page.content()
    write_text(out_path, html)
    return out_path


QUESTION_META_CLASSES = {
    "deferredfeedback",
    "adaptive",
    "adaptivenopenalty",
    "interactive",
    "interactivecountback",
    "immediatefeedback",
    "immediatecbm",
    "manualgraded",
    "complete",
    "incomplete",
    "invalid",
    "notanswered",
    "answered",
    "notyetanswered",
    "requiresgrading",
    "flagged",
}

QUESTION_STATUS_CLASSES = {
    "correct",
    "incorrect",
    "partiallycorrect",
    "wrong",
    "gradedright",
    "gradedpartial",
    "gradedwrong",
}


class QuizReviewLoopError(RuntimeError):
    pass


def node_text(node: Optional[Tag]) -> str:
    if not node:
        return ""
    return clean_text(node.get_text(" ", strip=True))


def node_text_without(node: Optional[Tag], selectors: List[str]) -> str:
    if not node:
        return ""
    clone = BeautifulSoup(str(node), "html.parser")
    for selector in selectors:
        for child in clone.select(selector):
            child.decompose()
    return clean_text(clone.get_text(" ", strip=True))


def dedupe_strings(values: List[str]) -> List[str]:
    result = []
    seen = set()
    for value in values:
        text = clean_text(value)
        if not text:
            continue
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        result.append(text)
    return result


def dedupe_dicts(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    result = []
    seen = set()
    for item in items:
        key = json.dumps(item, sort_keys=True, ensure_ascii=False)
        if key in seen:
            continue
        seen.add(key)
        result.append(item)
    return result


def extract_question_classes(question_node: Tag) -> List[str]:
    return [cls for cls in (question_node.get("class") or []) if cls and cls != "que"]


def extract_question_type(question_node: Tag) -> str:
    for cls in extract_question_classes(question_node):
        normalized = cls.strip().lower()
        if not normalized or normalized in QUESTION_META_CLASSES or normalized in QUESTION_STATUS_CLASSES:
            continue
        if normalized.startswith("qtype_"):
            normalized = normalized[6:]
        return normalized
    return "unknown"


def normalize_option_key(label: str) -> str:
    value = clean_text(label).rstrip(".:)")
    return value


def option_display(option: Dict[str, Any]) -> str:
    label = clean_text(option.get("label", ""))
    text = clean_text(option.get("text", ""))
    return clean_text(f"{label} {text}".strip())


def extract_icon_status(node: Optional[Tag]) -> str:
    if not node:
        return ""
    for tagged in node.select('i[aria-label], i[title], img[alt], span[aria-label]'):
        label = clean_text(tagged.get("aria-label") or tagged.get("title") or tagged.get("alt") or "")
        label_lc = label.lower()
        if label_lc == "correct":
            return "correct"
        if label_lc == "incorrect":
            return "incorrect"
        if "partially" in label_lc:
            return "partiallycorrect"
    return ""


def extract_checked_label(question_node, input_node) -> Optional[str]:
    input_id = input_node.get("id")
    if input_id:
        label = question_node.select_one(f'label[for="{input_id}"]')
        if label:
            return clean_text(label.get_text(" ", strip=True))

    labelledby = input_node.get("aria-labelledby")
    if labelledby:
        parts = []
        for label_id in labelledby.split():
            node = question_node.find(id=label_id)
            if node:
                text = clean_text(node.get_text(" ", strip=True))
                if text:
                    parts.append(text)
        if parts:
            return clean_text(" ".join(parts))

    parent_label = input_node.find_parent("label")
    if parent_label:
        return clean_text(parent_label.get_text(" ", strip=True))

    return None


def extract_control_prompt(question_node: Tag, control: Tag, fallback: str = "") -> str:
    control_id = control.get("id")
    if control_id:
        label = question_node.select_one(f'label[for="{control_id}"]')
        if label:
            text = node_text(label)
            if text:
                return text

    labelledby = control.get("aria-labelledby")
    if labelledby:
        parts = []
        for label_id in labelledby.split():
            node = question_node.find(id=label_id)
            if node:
                text = node_text_without(node, [".answernumber", ".icon", ".accesshide", ".sr-only"])
                if text:
                    parts.append(text)
        if parts:
            return clean_text(" ".join(parts))

    aria_label = clean_text(control.get("aria-label") or "")
    if aria_label:
        return aria_label

    row = control.find_parent("tr")
    if row:
        target_cell = control.find_parent(["td", "th"])
        if target_cell:
            siblings = []
            for cell in row.find_all(["th", "td"], recursive=False):
                if cell is target_cell:
                    continue
                text = node_text(cell)
                if text:
                    siblings.append(text)
            if siblings:
                return clean_text(" | ".join(siblings))

    subquestion = control.find_parent(lambda tag: isinstance(tag, Tag) and "subquestion" in (tag.get("class") or []))
    if subquestion:
        prompt = node_text_without(subquestion, ["select", "textarea", "input", ".feedback", ".outcome"])
        if prompt:
            return prompt

    parent_label = control.find_parent("label")
    if parent_label:
        text = node_text_without(parent_label, ["input", "select", "textarea"])
        if text:
            return text

    return fallback


def extract_choice_options(question_node: Tag) -> List[Dict[str, Any]]:
    candidates = question_node.select(
        ".answer > div, .answer > label, .answer > ul > li, .answer > ol > li, .answer table tr"
    )
    options: List[Dict[str, Any]] = []
    for row in candidates:
        input_node = row.select_one('input[type="radio"], input[type="checkbox"]')
        if not input_node:
            continue

        label_node = row.select_one('[data-region="answer-label"]') or row.select_one("label") or row
        label = node_text(row.select_one(".answernumber"))
        text = node_text_without(label_node, [".answernumber", ".icon", ".accesshide", ".sr-only"])
        if not text:
            text = extract_checked_label(question_node, input_node) or ""

        row_classes = {clean_text(cls).lower() for cls in (row.get("class") or []) if clean_text(cls)}
        status = ""
        if "correct" in row_classes:
            status = "correct"
        elif "partiallycorrect" in row_classes:
            status = "partiallycorrect"
        elif "incorrect" in row_classes or "wrong" in row_classes:
            status = "incorrect"
        else:
            status = extract_icon_status(row)

        option = {
            "key": normalize_option_key(label),
            "label": label,
            "text": text,
            "display": clean_text(f"{label} {text}".strip()),
            "value": clean_text(input_node.get("value") or ""),
            "input_type": clean_text(input_node.get("type") or ""),
            "selected": input_node.has_attr("checked"),
            "correct": status == "correct",
            "status": status,
        }

        feedback = node_text(row.select_one(".feedback, .specificfeedback"))
        if feedback:
            option["feedback"] = feedback

        options.append(option)

    return dedupe_dicts(options)


def extract_select_parts(question_node: Tag) -> List[Dict[str, Any]]:
    parts: List[Dict[str, Any]] = []
    for index, select in enumerate(question_node.select("select"), start=1):
        options = []
        selected_text = ""
        for option_index, option in enumerate(select.select("option"), start=1):
            text = node_text(option)
            if not text:
                continue
            option_data = {
                "index": option_index,
                "text": text,
                "value": clean_text(option.get("value") or ""),
                "selected": option.has_attr("selected"),
                "placeholder": not clean_text(option.get("value") or "") or text.lower().startswith("choose"),
            }
            if option_data["selected"] and not selected_text:
                selected_text = text
            options.append(option_data)

        if not options:
            continue

        part = {
            "kind": "select",
            "index": index,
            "name": clean_text(select.get("name") or ""),
            "prompt": extract_control_prompt(question_node, select, fallback=f"Blank {index}"),
            "response": selected_text,
            "options": options,
        }
        parts.append(part)

    return dedupe_dicts(parts)


def extract_text_input_parts(question_node: Tag) -> List[Dict[str, Any]]:
    parts: List[Dict[str, Any]] = []
    controls = question_node.select('textarea, input[type="text"], input[type="number"], input:not([type])')
    for index, control in enumerate(controls, start=1):
        control_type = clean_text(control.get("type") or control.name or "text").lower()
        if control_type in {"hidden", "radio", "checkbox", "button", "submit", "image"}:
            continue

        name = clean_text(control.get("name") or "")
        if ":sequencecheck" in name or name.endswith(":flagged") or name.endswith("_:flagged"):
            continue

        value = clean_text(control.get("value") or control.text or "")
        part = {
            "kind": "text" if control.name != "textarea" else "textarea",
            "index": index,
            "name": name,
            "prompt": extract_control_prompt(question_node, control, fallback=f"Response {index}"),
            "response": value,
            "input_type": control_type,
        }
        parts.append(part)

    return dedupe_dicts(parts)


def extract_dragdrop_parts(question_node: Tag, question_type: str) -> Tuple[List[Dict[str, Any]], List[str]]:
    parts: List[Dict[str, Any]] = []
    available_choices: List[str] = []

    if question_type not in {"ddwtos", "ddimageortext", "ddmarker", "ordering"} and not question_node.select_one(
        ".draghome, .drop, .dropzone, .place, [data-region='drop-zone'], [data-region='draghome']"
    ):
        return parts, available_choices

    choice_nodes = question_node.select(
        ".draghome .draghomechoice, .draghome .dragitem, .draghome .choice, .dragitems .dragitem, "
        ".dragchoices .choice, [data-region='draghome'] .dragitem, [data-region='draghome'] .choice"
    )
    available_choices = dedupe_strings([node_text(choice) for choice in choice_nodes])

    slot_nodes = question_node.select(
        ".drop, .dropzone, .place, [data-region='drop-zone'], [data-region='dropzone'], [class*='dropzone']"
    )
    for index, slot in enumerate(slot_nodes, start=1):
        response = node_text_without(slot, [".accesshide", ".sr-only", ".draghomechoice", ".placeholder"])
        prompt = clean_text(slot.get("aria-label") or slot.get("title") or "")
        if not response and not prompt:
            continue
        parts.append(
            {
                "kind": "dragdrop",
                "index": index,
                "prompt": prompt or f"Drop zone {index}",
                "response": response,
            }
        )

    return dedupe_dicts(parts), available_choices


def extract_right_answer_values(question_node: Tag) -> List[str]:
    rightanswer = question_node.select_one(".rightanswer")
    if not rightanswer:
        return []

    rich_values = [clean_text(node_text(node)).rstrip(" ,;") for node in rightanswer.select("li, p")]
    if rich_values:
        return dedupe_strings(rich_values)

    text = node_text(rightanswer)
    text = re.sub(r"^The correct answers?\s+(?:is|are):\s*", "", text, flags=re.I)
    text = clean_text(text).rstrip(" ,;")
    return [text] if text else []


def extract_available_choices(options: List[Dict[str, Any]], parts: List[Dict[str, Any]], dragdrop_choices: List[str]) -> List[str]:
    values = [option.get("display") or option.get("text") or "" for option in options]
    values.extend(dragdrop_choices)
    for part in parts:
        for option in part.get("options", []):
            if option.get("placeholder"):
                continue
            values.append(option.get("text", ""))
    return dedupe_strings(values)


def extract_response_values(options: List[Dict[str, Any]], parts: List[Dict[str, Any]], response_summary: str) -> List[str]:
    responses = [option_display(option) for option in options if option.get("selected")]
    for part in parts:
        response = clean_text(part.get("response") or "")
        prompt = clean_text(part.get("prompt") or "").rstrip(":")
        if not response:
            continue
        if prompt and not prompt.lower().startswith("response "):
            responses.append(f"{prompt}: {response}")
        else:
            responses.append(response)
    if response_summary:
        responses.append(response_summary)
    return dedupe_strings(responses)


def parse_quiz_question(question_node) -> Dict[str, Any]:
    question_name = clean_text(
        (question_node.select_one(".info .no") or question_node.select_one(".qno") or question_node.select_one(".no")).get_text(" ", strip=True)
        if (question_node.select_one(".info .no") or question_node.select_one(".qno") or question_node.select_one(".no"))
        else ""
    )
    question_text = clean_text(
        question_node.select_one(".qtext").get_text(" ", strip=True)
        if question_node.select_one(".qtext")
        else question_node.get_text(" ", strip=True)
    )
    state = clean_text(question_node.select_one(".state").get_text(" ", strip=True) if question_node.select_one(".state") else "")
    grade = clean_text(question_node.select_one(".grade").get_text(" ", strip=True) if question_node.select_one(".grade") else "")
    question_type = extract_question_type(question_node)
    question_classes = extract_question_classes(question_node)

    options = extract_choice_options(question_node)
    select_parts = extract_select_parts(question_node)
    text_parts = extract_text_input_parts(question_node)
    dragdrop_parts, dragdrop_choices = extract_dragdrop_parts(question_node, question_type)
    parts = dedupe_dicts(select_parts + text_parts + dragdrop_parts)
    response_summary = clean_text(question_node.select_one(".responsesummary").get_text(" ", strip=True) if question_node.select_one(".responsesummary") else "")
    responses = extract_response_values(options, parts, response_summary)
    right_answer = clean_text(question_node.select_one(".rightanswer").get_text(" ", strip=True) if question_node.select_one(".rightanswer") else "")
    right_answer_values = extract_right_answer_values(question_node)
    specific_feedback = clean_text(question_node.select_one(".specificfeedback").get_text(" ", strip=True) if question_node.select_one(".specificfeedback") else "")
    general_feedback = clean_text(question_node.select_one(".generalfeedback").get_text(" ", strip=True) if question_node.select_one(".generalfeedback") else "")
    available_choices = extract_available_choices(options, parts, dragdrop_choices)
    selected_options = [option_display(option) for option in options if option.get("selected")]
    correct_options = [option_display(option) for option in options if option.get("correct")]

    return {
        "question": question_name,
        "text": question_text,
        "type": question_type,
        "classes": question_classes,
        "state": state,
        "grade": grade,
        "responses": responses,
        "selected_options": selected_options,
        "correct_options": correct_options,
        "options": options,
        "parts": parts,
        "available_choices": available_choices,
        "right_answer": right_answer,
        "right_answer_values": right_answer_values,
        "specific_feedback": specific_feedback,
        "general_feedback": general_feedback,
    }


def parse_quiz_view_page(html: str, page_url: str) -> Dict[str, Any]:
    soup = BeautifulSoup(html, "html.parser")
    title = clean_text(soup.title.get_text(" ", strip=True) if soup.title else "")
    intro = clean_text(soup.select_one(".quizinfo, .quizintro, .box.py-3.quizattempt").get_text(" ", strip=True) if soup.select_one(".quizinfo, .quizintro, .box.py-3.quizattempt") else "")

    review_links = []
    attempt_links = []
    for anchor in soup.select('a[href]'):
        href = anchor.get("href") or ""
        absolute = urljoin(page_url, href)
        if "/mod/quiz/review.php" in absolute:
            review_links.append(absolute)
        elif "/mod/quiz/attempt.php" in absolute or "/mod/quiz/startattempt.php" in absolute:
            attempt_links.append(absolute)

    attempts = []
    for row in soup.select("table.quizattemptsummary tbody tr"):
        cells = [clean_text(cell.get_text(" ", strip=True)) for cell in row.select("th, td")]
        if not any(cells):
            continue
        row_links = [urljoin(page_url, a.get("href")) for a in row.select('a[href]') if a.get("href")]
        attempts.append({"cells": cells, "links": row_links})

    unique_review_links = list(dict.fromkeys(review_links))
    unique_attempt_links = list(dict.fromkeys(attempt_links))

    return {
        "title": title,
        "url": page_url,
        "intro": intro,
        "attempts": attempts,
        "review_links": unique_review_links,
        "attempt_links": unique_attempt_links,
    }


def parse_quiz_review_page(html: str, page_url: str) -> Dict[str, Any]:
    soup = BeautifulSoup(html, "html.parser")
    title = clean_text(soup.title.get_text(" ", strip=True) if soup.title else "")
    questions = [parse_quiz_question(node) for node in soup.select(".que")]
    current_key = review_page_key(page_url)
    next_links = extract_review_navigation_links(soup, page_url, current_key)

    return {
        "title": title,
        "url": page_url,
        "questions": questions,
        "review_key": review_key_to_dict(current_key),
        "next_links": list(dict.fromkeys(next_links)),
    }


def normalize_review_url(url: str) -> Optional[str]:
    parsed = urlparse(url)
    if "/mod/quiz/review.php" not in parsed.path.lower():
        return None

    query = parse_qs(parsed.query)
    attempt = query.get("attempt", [None])[0]
    if not attempt:
        return None

    page = query.get("page", [None])[0]
    raw_showall = query.get("showall", [None])[0]
    showall: Optional[str]
    if raw_showall is None:
        showall = None
    else:
        showall_lc = str(raw_showall).strip().lower()
        if showall_lc in {"1", "true", "yes", "on"}:
            showall = "1"
        elif showall_lc in {"0", "false", "no", "off"}:
            showall = "0"
        else:
            showall = clean_text(str(raw_showall))

    normalized_pairs = [("attempt", str(attempt))]
    if showall == "1":
        normalized_pairs.append(("showall", "1"))
    else:
        normalized_pairs.append(("page", str(page or "0")))

    normalized_query = "&".join([f"{key}={value}" for key, value in normalized_pairs])
    return f"{parsed.scheme}://{parsed.netloc}{parsed.path}?{normalized_query}"


def review_key_from_normalized_url(normalized_url: str) -> Optional[Tuple[str, str, str]]:
    if not normalized_url:
        return None
    parsed = urlparse(normalized_url)
    query = parse_qs(parsed.query)
    attempt = str(query.get("attempt", [None])[0] or "")
    if not attempt:
        return None
    if "showall" in query:
        return (attempt, "showall", str(query.get("showall", ["1"])[0]))
    return (attempt, "page", str(query.get("page", ["0"])[0]))


def review_page_key(url: str) -> Optional[Tuple[str, str, str]]:
    normalized = normalize_review_url(url)
    if not normalized:
        return None
    return review_key_from_normalized_url(normalized)


def review_key_to_dict(review_key: Optional[Tuple[str, str, str]]) -> Optional[Dict[str, str]]:
    if not review_key:
        return None
    return {"attempt": review_key[0], "mode": review_key[1], "value": review_key[2]}


def extract_review_navigation_links(soup: BeautifulSoup, page_url: str, current_key: Optional[Tuple[str, str, str]]) -> List[str]:
    if not current_key:
        return []

    current_attempt, current_mode, _ = current_key
    showall_links: List[str] = []
    page_links: List[str] = []
    selectors = [
        ".othernav a[href]",
        ".quizreviewpager a[href]",
        ".mod_quiz-next-nav[href]",
        ".mod_quiz-prev-nav[href]",
        ".qnbutton[href]",
        ".qn_buttons a[href]",
        ".questionnav a[href]",
        "a[href*='/mod/quiz/review.php']",
    ]

    seen_normalized = set()
    for selector in selectors:
        for anchor in soup.select(selector):
            href = anchor.get("href") or ""
            absolute = urljoin(page_url, href)
            normalized = normalize_review_url(absolute)
            if not normalized or normalized in seen_normalized:
                continue
            seen_normalized.add(normalized)

            review_key = review_key_from_normalized_url(normalized)
            if not review_key or review_key[0] != current_attempt or review_key == current_key:
                continue

            if review_key[1] == "showall" and review_key[2] == "1":
                showall_links.append(normalized)
            elif review_key[1] == "page":
                page_links.append(normalized)

    if current_mode == "showall":
        return []

    return list(dict.fromkeys(showall_links + page_links))


def extract_attempt_review_seeds(intro_data: Dict[str, Any]) -> List[str]:
    seeds = []
    for review_link in intro_data.get("review_links", []):
        normalized = normalize_review_url(review_link)
        if normalized:
            seeds.append(normalized)

    for attempt in intro_data.get("attempts", []):
        for link in attempt.get("links", []):
            normalized = normalize_review_url(link)
            if normalized:
                seeds.append(normalized)

    return list(dict.fromkeys(seeds))


def save_quiz_bundle(page, url: str, destination_dir: Path, bundle_name: str) -> Dict[str, Any]:
    quiz_dir = destination_dir / sanitize(bundle_name)
    quiz_dir.mkdir(parents=True, exist_ok=True)

    page.goto(url, wait_until="networkidle", timeout=120000)
    intro_html_path = quiz_dir / "quiz_intro.html"
    intro_html_path.write_text(page.content(), encoding="utf-8")
    intro_data = parse_quiz_view_page(page.content(), page.url)

    attempts_dir = quiz_dir / "attempts"
    attempts_dir.mkdir(parents=True, exist_ok=True)

    review_queue = extract_attempt_review_seeds(intro_data)
    queued_review_urls = set(review_queue)
    visited_review_urls = set()
    visited_attempt_pages = set()
    review_pages = []
    review_index = 1
    attempt_page_counts: Dict[str, int] = {}
    max_pages_per_attempt = 25
    max_total_review_pages = 50
    max_duplicate_page_hits = 2
    duplicate_page_hits = 0
    navigation_trace: List[str] = []

    while review_queue:
        review_url = review_queue.pop(0)
        queued_review_urls.discard(review_url)
        normalized_review_url = normalize_review_url(review_url)
        if not normalized_review_url:
            continue
        requested_review_key = review_key_from_normalized_url(normalized_review_url)
        if normalized_review_url in visited_review_urls:
            continue
        visited_review_urls.add(normalized_review_url)
        if len(visited_attempt_pages) >= max_total_review_pages:
            raise QuizReviewLoopError(
                f"Aborted quiz export after {len(visited_attempt_pages)} review pages because the review navigation exceeded the safety limit."
            )

        page.goto(normalized_review_url, wait_until="networkidle", timeout=120000)
        review_html = page.content()
        review_data = parse_quiz_review_page(review_html, page.url)
        actual_review_key = review_page_key(page.url) or review_key_from_normalized_url(normalized_review_url)
        if not actual_review_key:
            raise RuntimeError(f"Quiz review navigation landed on a non-review page: {page.url}")

        attempt_id, review_mode, review_value = actual_review_key
        navigation_trace.append(f"{attempt_id}:{review_mode}={review_value}")
        if len(navigation_trace) > 12:
            navigation_trace = navigation_trace[-12:]

        if actual_review_key in visited_attempt_pages:
            duplicate_page_hits += 1
            redirected_to_previous_page = requested_review_key and actual_review_key != requested_review_key
            if redirected_to_previous_page or duplicate_page_hits >= max_duplicate_page_hits:
                trace = " -> ".join(navigation_trace[-8:])
                raise QuizReviewLoopError(
                    f"Detected repeated quiz review navigation at attempt {attempt_id} ({review_mode}={review_value}). "
                    f"Recent trace: {trace}"
                )
            continue

        duplicate_page_hits = 0
        visited_attempt_pages.add(actual_review_key)
        attempt_page_counts.setdefault(attempt_id, 0)
        attempt_page_counts[attempt_id] += 1
        if attempt_page_counts[attempt_id] > max_pages_per_attempt:
            trace = " -> ".join(navigation_trace[-8:])
            raise QuizReviewLoopError(
                f"Detected a probable navigation loop while exporting quiz attempt {attempt_id}. "
                f"Visited more than {max_pages_per_attempt} unique review pages for one attempt. Recent trace: {trace}"
            )

        page_label = review_value if review_mode == "page" else f"showall_{review_value}"
        review_path = attempts_dir / f"attempt_{sanitize(str(attempt_id))}_page_{sanitize(str(page_label))}.html"
        review_path.write_text(review_html, encoding="utf-8")

        review_pages.append(
            {
                "attempt": attempt_id,
                "page": review_value,
                "mode": review_mode,
                "path": str(review_path),
                "url": page.url,
                "questions": review_data.get("questions", []),
            }
        )
        review_index += 1

        for next_link in review_data.get("next_links", []):
            normalized_next = normalize_review_url(next_link)
            if not normalized_next:
                continue
            next_key = review_key_from_normalized_url(normalized_next)
            if not next_key:
                continue
            if next_key[0] != str(attempt_id):
                continue
            if next_key in visited_attempt_pages:
                continue
            if normalized_next in visited_review_urls:
                continue
            if normalized_next in queued_review_urls:
                continue
            review_queue.append(normalized_next)
            queued_review_urls.add(normalized_next)

    export = {
        "status": "saved_quiz",
        "path": str(quiz_dir),
        "url": url,
        "intro_html": str(intro_html_path),
        "intro": intro_data,
        "review_pages": review_pages,
        "review_count": len(review_pages),
    }

    write_text(quiz_dir / "quiz_export.json", json.dumps(export, indent=2, ensure_ascii=False))

    md_lines = [f"# {bundle_name}", "", f"Source: {url}", ""]
    if intro_data.get("intro"):
        md_lines += ["## Intro", "", intro_data["intro"], ""]
    if intro_data.get("attempts"):
        md_lines += ["## Attempt Summary", ""]
        for idx, attempt in enumerate(intro_data["attempts"], start=1):
            md_lines.append(f"- Attempt {idx}: {' | '.join(attempt.get('cells', []))}")
        md_lines.append("")
    if review_pages:
        md_lines += ["## Review Pages", ""]
        for review in review_pages:
            md_lines.append(f"### Attempt {review['attempt']} Page {review['page']}")
            md_lines.append("")
            for question in review.get("questions", []):
                title = question.get("question") or "Question"
                qtype = question.get("type") or "unknown"
                md_lines.append(f"#### {title} [{qtype}]")
                md_lines.append("")
                md_lines.append(question.get("text") or "")
                md_lines.append("")
                if question.get("state"):
                    md_lines.append(f"State: {question['state']}")
                if question.get("grade"):
                    md_lines.append(f"Grade: {question['grade']}")
                if question.get("responses"):
                    md_lines.append(f"Response: {'; '.join(question['responses'])}")
                if question.get("right_answer"):
                    md_lines.append(f"Right answer: {question['right_answer']}")
                if question.get("options"):
                    md_lines.append("")
                    md_lines.append("Options:")
                    for option in question["options"]:
                        markers = []
                        if option.get("selected"):
                            markers.append("selected")
                        if option.get("correct"):
                            markers.append("correct")
                        marker_text = f" ({', '.join(markers)})" if markers else ""
                        md_lines.append(f"- {option.get('display') or option.get('text')}{marker_text}")
                if question.get("parts"):
                    md_lines.append("")
                    md_lines.append("Parts:")
                    for part in question["parts"]:
                        prompt = part.get("prompt") or f"Part {part.get('index')}"
                        response = part.get("response") or ""
                        md_lines.append(f"- {prompt}: {response}")
                        options = [opt.get("text", "") for opt in part.get("options", []) if not opt.get("placeholder")]
                        if options:
                            md_lines.append(f"  Choices: {'; '.join(dedupe_strings(options))}")
                if question.get("available_choices") and not question.get("options"):
                    md_lines.append("")
                    md_lines.append(f"Available choices: {'; '.join(question['available_choices'])}")
                if question.get("specific_feedback"):
                    md_lines.append(f"Specific feedback: {question['specific_feedback']}")
                if question.get("general_feedback"):
                    md_lines.append(f"General feedback: {question['general_feedback']}")
                md_lines.append("")
            md_lines.append("")
    else:
        md_lines += ["## Review Pages", "", "No review pages were visible from the quiz landing page. The intro page was still saved.", ""]

    write_text(quiz_dir / "quiz_export.md", "\n".join(md_lines))
    return export


def direct_download(url: str, target_path: Path) -> int:
    ensure_parent(target_path)
    with requests.get(url, stream=True, timeout=180) as response:
        response.raise_for_status()
        with target_path.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    handle.write(chunk)
    return target_path.stat().st_size


def resolve_file_response(page, url: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    captured: List[Dict[str, Any]] = []
    fallback_url = None

    def on_response(response):
        nonlocal fallback_url
        request = response.request
        resource_type = getattr(request, "resource_type", "")
        if resource_type and resource_type != "document":
            return
        response_url = response.url
        headers = dict(response.headers)
        content_type = headers.get("content-type", "")
        status = response.status
        if status == 200:
            captured.append(
                {
                    "url": response_url,
                    "status": status,
                    "headers": headers,
                    "content_type": content_type,
                }
            )
        if response_url.startswith("http"):
            fallback_url = response_url

    page.on("response", on_response)
    try:
        try:
            page.goto(url, wait_until="load", timeout=120000)
        except Exception:
            pass
        time.sleep(2)
    finally:
        try:
            page.remove_listener("response", on_response)
        except Exception:
            pass

    if captured:
        return captured[-1], fallback_url
    return None, fallback_url


def build_output_path(destination_dir: Optional[str], out_path: Optional[str], filename: Optional[str], fallback_name: str, suffix: str = "") -> Path:
    if out_path:
        return Path(out_path)

    if destination_dir:
        base_dir = Path(destination_dir)
    else:
        base_dir = Path.cwd()

    chosen = sanitize(filename or fallback_name)
    if suffix and not chosen.lower().endswith(suffix.lower()):
        chosen = f"{chosen}{suffix}"
    return base_dir / chosen


def extract_download_candidates(page) -> List[Dict[str, str]]:
    raw_candidates = page.evaluate(
        """() => {
            const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
            const selectors = [
                'a[href*="pluginfile.php"]',
                'a[href*="forcedownload=1"]',
                '.foldertree a[href]',
                '.fp-filename a[href]',
                'a[download]',
                'a[href]'
            ];
            const seen = new Set();
            const links = [];
            for (const selector of selectors) {
                for (const anchor of document.querySelectorAll(selector)) {
                    const href = anchor.href || '';
                    const text = clean(anchor.innerText || anchor.textContent || anchor.getAttribute('download') || '');
                    const key = `${href}||${text}`;
                    if (!href || seen.has(key)) {
                        continue;
                    }
                    seen.add(key);
                    links.push({ href, text, title: clean(anchor.title || '') });
                }
            }
            return links;
        }"""
    )

    payload = {"url": page.url, "links": normalize_links(raw_candidates)}
    page_host = get_url_host(payload.get("url", ""))
    candidates = []
    seen = set()
    for link in payload.get("links", []):
        href = link.get("href", "")
        text = link.get("text", "")
        if looks_like_navigation_link(link, page_host) and not is_probable_file_link(href, text):
            continue
        if not is_probable_file_link(href, text):
            continue
        key = (href, text)
        if key in seen:
            continue
        seen.add(key)
        candidates.append(link)
    return candidates


def download_folder_page(page, url: str, destination_dir: Path) -> List[Dict[str, Any]]:
    page.goto(url, wait_until="networkidle", timeout=120000)
    candidates = extract_download_candidates(page)
    results: List[Dict[str, Any]] = []

    if not candidates:
        raise RuntimeError("No downloadable child links were found on the folder page.")

    for candidate in candidates:
        href = candidate.get("href", "")
        text = candidate.get("text", "") or "download"
        try:
            resolved, _ = resolve_file_response(page, href)
            if not resolved:
                raise RuntimeError("No direct file response was captured for child link.")

            output_name = filename_from_response(resolved["url"], resolved["headers"], text)
            target_path = build_output_path(str(destination_dir), None, output_name, output_name)
            size = direct_download(resolved["url"], target_path)
            results.append(
                {
                    "status": "downloaded",
                    "source_url": href,
                    "resolved_url": resolved["url"],
                    "path": str(target_path),
                    "size": size,
                }
            )
        except Exception as exc:
            results.append(
                {
                    "status": "error",
                    "source_url": href,
                    "name": text,
                    "error": f"{type(exc).__name__}: {exc}",
                }
            )

    return results


def classify_moodle_category(name: str, classes: str) -> Tuple[str, str]:
    name_lc = (name or "").lower()
    classes_lc = (classes or "").lower()

    if "folder" in classes_lc:
        if "note" in name_lc:
            return "Handwritten Notes", "folder"
        if "slide" in name_lc:
            return "Lecture Slides", "folder"
        if "homework" in name_lc:
            return "Homework", "folder"
        if "exam" in name_lc:
            return "Exam Materials", "folder"
        return "Folder Materials", "folder"

    if "resource" in classes_lc:
        if "note" in name_lc and "lecture" in name_lc:
            return "Lecture Notes", "file"
        if "note" in name_lc:
            return "Handwritten Notes", "file"
        if "slide" in name_lc:
            return "Lecture Slides", "file"
        if "equation" in name_lc or "reference" in name_lc:
            return "Reference Sheets", "file"
        if "pst" in name_lc or "problem" in name_lc:
            if "solution" in name_lc:
                return "Problem Sheet Solutions", "file"
            return "Problem Sheets", "file"
        if "quiz" in name_lc:
            if "solution" in name_lc:
                return "Quiz Solutions", "file"
            return "Quiz Materials", "file"
        if "homework" in name_lc:
            return "Homework", "file"
        if "exam" in name_lc or "midterm" in name_lc:
            return "Exam Materials", "file"
        if "solution" in name_lc:
            return "Solutions", "file"
        return "Files", "file"

    if any(token in classes_lc for token in ("lti", "panoptocourseembed")):
        return "Lecture Recordings", "shortcut"
    if "page" in classes_lc:
        return "Pages", "page"
    if "url" in classes_lc:
        return "Links", "shortcut"
    if "forum" in classes_lc:
        return "Forums", "shortcut"
    if "quiz" in classes_lc:
        return "Quizzes", "quiz"
    if any(token in classes_lc for token in ("feedback", "questionnaire", "assign")):
        return "Interactive Activities", "shortcut"
    return "Other", "shortcut"


def infer_moodle_spec(page, limit: Optional[int] = None) -> Dict[str, Any]:
    payload = page.evaluate(
        """() => {
            const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
            const sections = [...document.querySelectorAll('li.section, .course-section')].map((section, index) => {
                const titleNode = section.querySelector('.sectionname, .section-title, h3, h4');
                const title = clean(titleNode?.innerText) || `Section ${index + 1}`;
                const items = [...section.querySelectorAll('li.activity')].map(activity => {
                    const anchor = activity.querySelector('a[href]');
                    const nameNode = activity.querySelector('.instancename, .activityname');
                    return {
                        name: clean(nameNode?.innerText) || clean(anchor?.innerText) || '',
                        href: anchor?.href || '',
                        classes: activity.className || ''
                    };
                });
                return { title, items };
            });
            return { title: document.title, url: location.href, sections };
        }"""
    )

    items = []
    for index, section in enumerate(payload.get("sections", []), start=1):
        section_title = section.get("title") or f"Section {index}"
        section_dir = f"{index:02d}_{sanitize(section_title)}"
        for activity in section.get("items", []):
            href = activity.get("href", "")
            name = activity.get("name", "")
            if not href:
                continue
            if not name and (href.endswith("#") or href == payload.get("url") or href.startswith(f"{payload.get('url')}#")):
                continue
            if not name:
                continue
            category, mode = classify_moodle_category(name, activity.get("classes", ""))
            item = {
                "url": href,
                "directory": f"{section_dir}\\{sanitize(category)}",
                "mode": mode,
                "filename": sanitize(name) if name and mode in ("page", "shortcut", "quiz", "folder") else None,
                "name": name,
                "section": section_title,
                "category": category,
            }
            items.append(item)
            if limit and len(items) >= limit:
                break
        if limit and len(items) >= limit:
            break

    return {
        "site": "moodle",
        "title": payload.get("title"),
        "url": payload.get("url"),
        "suggested_root": clean_title_for_root(payload.get("title") or "moodle_dump"),
        "count": len(items),
        "items": items,
    }


def infer_sharepoint_spec(page, limit: Optional[int] = None) -> Dict[str, Any]:
    payload = page_links_payload(page)
    page_host = get_url_host(payload.get("url", ""))
    items = []
    for link in payload.get("links", []):
        href = link.get("href", "")
        text = link.get("text", "")
        link_host = get_url_host(href)
        if not href or (link_host and "sharepoint.com" not in link_host and "onedrive.live.com" not in link_host):
            continue
        if looks_like_navigation_link(link, page_host):
            continue

        if is_probable_file_link(href, text):
            category = "Documents"
            mode = "auto"
        elif is_page_like_link(href):
            category = "Pages"
            mode = "page"
        else:
            category = "Links"
            mode = "shortcut"

        items.append(
            {
                "url": href,
                "directory": sanitize(category),
                "mode": mode,
                "filename": sanitize(text) if text and mode in ("page", "shortcut") else None,
                "name": text,
                "category": category,
            }
        )
        if limit and len(items) >= limit:
            break

    return {
        "site": "sharepoint",
        "title": payload.get("title"),
        "url": payload.get("url"),
        "suggested_root": clean_title_for_root(payload.get("title") or "sharepoint_dump"),
        "count": len(items),
        "items": items,
    }


def infer_panopto_spec(page, limit: Optional[int] = None) -> Dict[str, Any]:
    payload = page_links_payload(page)
    items = []
    for link in payload.get("links", []):
        href = link.get("href", "")
        text = link.get("text", "")
        if "panopto" not in get_url_host(href) and "panopto" not in href.lower():
            continue
        if looks_like_navigation_link(link, get_url_host(payload.get("url", ""))):
            continue

        if is_probable_file_link(href, text):
            category = "Downloads"
            mode = "auto"
        elif "viewer.aspx" in href.lower() or "pages/sessions" in href.lower():
            category = "Sessions"
            mode = "shortcut"
        else:
            category = "Links"
            mode = "shortcut"

        items.append(
            {
                "url": href,
                "directory": sanitize(category),
                "mode": mode,
                "filename": sanitize(text) if text else None,
                "name": text,
                "category": category,
            }
        )
        if limit and len(items) >= limit:
            break

    return {
        "site": "panopto",
        "title": payload.get("title"),
        "url": payload.get("url"),
        "suggested_root": clean_title_for_root(payload.get("title") or "panopto_dump"),
        "count": len(items),
        "items": items,
    }


def infer_generic_spec(page, limit: Optional[int] = None) -> Dict[str, Any]:
    payload = page_links_payload(page)
    page_host = get_url_host(payload.get("url", ""))
    items = []
    for link in payload.get("links", []):
        href = link.get("href", "")
        text = link.get("text", "")
        if looks_like_navigation_link(link, page_host):
            continue
        if is_probable_file_link(href, text):
            category = "Files"
            mode = "auto"
        elif is_page_like_link(href):
            category = "Pages"
            mode = "page"
        else:
            category = "Links"
            mode = "shortcut"

        items.append(
            {
                "url": href,
                "directory": sanitize(category),
                "mode": mode,
                "filename": sanitize(text) if text and mode in ("page", "shortcut") else None,
                "name": text,
                "category": category,
            }
        )
        if limit and len(items) >= limit:
            break

    return {
        "site": "generic",
        "title": payload.get("title"),
        "url": payload.get("url"),
        "suggested_root": clean_title_for_root(payload.get("title") or "auth_dump"),
        "count": len(items),
        "items": items,
    }


def detect_site(page_url: str, title: str) -> str:
    host = get_url_host(page_url)
    title_lc = (title or "").lower()
    if "moodle" in host or "moodle" in title_lc:
        return "moodle"
    if "sharepoint.com" in host or "onedrive.live.com" in host or "sharepoint" in title_lc:
        return "sharepoint"
    if "panopto" in host or "panopto" in title_lc:
        return "panopto"
    return "generic"


def infer_spec(page, site: str, limit: Optional[int] = None) -> Dict[str, Any]:
    chosen_site = site.lower()
    current_title = page.title()
    current_url = page.url
    if chosen_site == "auto":
        chosen_site = detect_site(current_url, current_title)

    if chosen_site == "moodle":
        spec = infer_moodle_spec(page, limit=limit)
    elif chosen_site == "sharepoint":
        spec = infer_sharepoint_spec(page, limit=limit)
    elif chosen_site == "panopto":
        spec = infer_panopto_spec(page, limit=limit)
    else:
        spec = infer_generic_spec(page, limit=limit)

    spec["site"] = chosen_site
    spec["count"] = len(spec.get("items", []))
    return spec


def cmd_extension_install(args) -> Dict[str, Any]:
    extensions_root = ensure_directory(Path(args.extensions_root).expanduser().resolve())
    packages_root = ensure_directory(extensions_root / "packages" / args.browser)
    unpacked_root = ensure_directory(extensions_root / "unpacked" / args.browser)

    source_count = sum(
        1
        for value in [clean_text(args.source_url or ""), clean_text(args.package_path or ""), clean_text(args.directory_path or "")]
        if value
    )
    if source_count != 1:
        raise RuntimeError("Use exactly one extension source: --source-url, --package-path, or --directory-path.")

    requested_name = clean_text(args.name or "")
    source_label = requested_name or Path(clean_text(args.package_path or args.directory_path or args.source_url or "")).stem or "extension"
    slug = slugify_extension_name(source_label)

    package_store_dir = packages_root / slug
    unpacked_store_dir = unpacked_root / slug
    ensure_clean_directory(package_store_dir, overwrite=args.overwrite)
    ensure_clean_directory(unpacked_store_dir, overwrite=args.overwrite)

    stored_package_path = ""
    if args.source_url:
        downloaded_path = download_extension_package(args.source_url, package_store_dir, slug)
        unpack_extension_archive(downloaded_path, unpacked_store_dir)
        stored_package_path = str(downloaded_path)
    elif args.package_path:
        source_package_path = Path(args.package_path).expanduser().resolve()
        if not source_package_path.exists():
            raise RuntimeError(f"Package path does not exist: {source_package_path}")
        package_copy_path = package_store_dir / source_package_path.name
        shutil.copy2(source_package_path, package_copy_path)
        unpack_extension_archive(package_copy_path, unpacked_store_dir)
        stored_package_path = str(package_copy_path)
    elif args.directory_path:
        source_directory_path = Path(args.directory_path).expanduser().resolve()
        if not source_directory_path.exists():
            raise RuntimeError(f"Directory path does not exist: {source_directory_path}")
        if not source_directory_path.is_dir():
            raise RuntimeError(f"Directory path is not a directory: {source_directory_path}")
        shutil.copytree(source_directory_path, unpacked_store_dir, dirs_exist_ok=True)
    else:
        raise RuntimeError("Provide --source-url, --package-path, or --directory-path.")

    extension_root = find_extension_manifest_root(unpacked_store_dir)
    manifest = inspect_browser_extension_manifest(extension_root)
    extension_name = requested_name or manifest["name"] or slug

    return {
        "status": "installed",
        "name": extension_name,
        "slug": slug,
        "browser": args.browser,
        "source_url": clean_text(args.source_url or ""),
        "package_path": stored_package_path,
        "extension_root": str(extension_root),
        "manifest": manifest,
    }


def cmd_extension_runtime_list(args) -> Dict[str, Any]:
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page = context.new_page()
        try:
            ensure_chatgpt_runtime_resilience(page)
            items = list_runtime_browser_extensions(
                page,
                args.browser,
                user_data_dir=clean_text(args.user_data_dir or ""),
                profile_directory=clean_text(args.profile_directory or "") or "Default",
            )
            return {
                "status": "ok",
                "browser": args.browser,
                "count": len(items),
                "items": items,
            }
        finally:
            page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_extension_open(args) -> Dict[str, Any]:
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page = context.new_page()
        try:
            ensure_chatgpt_runtime_resilience(page)
            runtime_entries = list_runtime_browser_extensions(
                page,
                args.browser,
                user_data_dir=clean_text(args.user_data_dir or ""),
                profile_directory=clean_text(args.profile_directory or "") or "Default",
            )
            runtime_entry = find_runtime_browser_extension(runtime_entries, extension_id=args.extension_id, name=args.name)
            target_url = build_runtime_extension_url(runtime_entry["id"], page_path=args.page_path, url=args.url)
            page.goto(target_url, wait_until="domcontentloaded", timeout=120000)
            page.wait_for_timeout(900)
            return {
                "status": "ok",
                "browser": args.browser,
                "extension": runtime_entry,
                "url": page.url,
                "title": clean_text(page.title() or ""),
            }
        finally:
            page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_extension_click(args) -> Dict[str, Any]:
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page = context.new_page()
        try:
            ensure_chatgpt_runtime_resilience(page)
            runtime_entries = list_runtime_browser_extensions(
                page,
                args.browser,
                user_data_dir=clean_text(args.user_data_dir or ""),
                profile_directory=clean_text(args.profile_directory or "") or "Default",
            )
            runtime_entry = find_runtime_browser_extension(runtime_entries, extension_id=args.extension_id, name=args.name)
            target_url = build_runtime_extension_url(runtime_entry["id"], page_path=args.page_path, url=args.url)
            page.goto(target_url, wait_until="domcontentloaded", timeout=120000)
            page.wait_for_timeout(900)
            locator, matched_label = find_visible_page_control(page, selector=args.selector or "", text_contains=args.text_contains or "")
            click_mode = safe_click(locator, timeout=max(args.timeout_ms, 1000), reason="extension_click")
            page.wait_for_timeout(800)
            return {
                "status": "ok",
                "browser": args.browser,
                "extension": runtime_entry,
                "click_mode": click_mode,
                "matched_label": matched_label,
                "url": page.url,
                "title": clean_text(page.title() or ""),
            }
        finally:
            page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_links(args) -> Dict[str, Any]:
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            if args.url:
                page.goto(args.url, wait_until="networkidle", timeout=120000)
            payload = page_links_payload(page)
            if args.out:
                out_path = Path(args.out)
                write_text(out_path, json.dumps(payload, indent=2, ensure_ascii=False))
                payload["saved_to"] = str(out_path)
            return payload
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_infer_spec(args) -> Dict[str, Any]:
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            if args.url:
                page.goto(args.url, wait_until="networkidle", timeout=120000)
            spec = infer_spec(page, args.site, limit=args.limit)
            if args.out:
                out_path = Path(args.out)
                write_text(out_path, json.dumps(spec, indent=2, ensure_ascii=False))
                spec["saved_to"] = str(out_path)
            return spec
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_save_page(args) -> Dict[str, Any]:
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page, created = choose_page(context, page_url_contains=args.page_url_contains)
        try:
            if args.url:
                page.goto(args.url, wait_until="networkidle", timeout=120000)
            out_path = build_output_path(args.destination_dir, args.out, args.filename, sanitize(page.title() or "page"), ".html")
            saved_path = save_html(page, out_path)
            return {"status": "saved_html", "path": str(saved_path), "url": page.url, "title": page.title()}
        finally:
            if created:
                page.close()
    finally:
        browser.close()
        playwright.stop()


def cmd_download(args) -> Dict[str, Any]:
    mode = args.mode.lower()
    playwright, browser = connect_browser(args.cdp)
    try:
        context = choose_context(browser)
        page = context.new_page()
        try:
            if mode == "shortcut":
                out_path = build_output_path(args.destination_dir, args.out, args.filename, "link", ".url")
                write_shortcut(out_path, args.url)
                return {"status": "saved_shortcut", "path": str(out_path), "url": args.url}

            if mode == "quiz":
                destination = Path(args.destination_dir) if args.destination_dir else Path.cwd()
                destination.mkdir(parents=True, exist_ok=True)
                bundle_name = args.filename or "quiz"
                return save_quiz_bundle(page, args.url, destination, bundle_name)

            if mode == "page":
                page.goto(args.url, wait_until="networkidle", timeout=120000)
                fallback_name = args.filename or sanitize(page.title() or "page")
                out_path = build_output_path(args.destination_dir, args.out, fallback_name, fallback_name, ".html")
                saved_path = save_html(page, out_path)
                return {
                    "status": "saved_html",
                    "path": str(saved_path),
                    "url": args.url,
                    "page_url": page.url,
                    "title": page.title(),
                }

            if mode == "folder":
                destination = Path(args.destination_dir) if args.destination_dir else Path.cwd()
                results = download_folder_page(page, args.url, destination)
                return {
                    "status": "downloaded_folder",
                    "path": str(destination),
                    "url": args.url,
                    "count": len(results),
                    "results": results,
                }

            resolved, fallback_url = resolve_file_response(page, args.url)

            if resolved:
                content_type = (resolved["content_type"] or "").lower()
                headers = resolved["headers"]
                resolved_url = resolved["url"]
                has_content_disposition = bool(headers.get("content-disposition"))
                fileish_url = is_probable_file_link(resolved_url, args.filename or "")
                downloadable_document = has_content_disposition or fileish_url or ("text/html" not in content_type)

                if downloadable_document:
                    fallback_name = args.filename or "download"
                    output_name = filename_from_response(resolved_url, headers, fallback_name)
                    target_path = build_output_path(args.destination_dir, args.out, output_name, output_name)
                    size = direct_download(resolved_url, target_path)
                    return {
                        "status": "downloaded",
                        "path": str(target_path),
                        "url": args.url,
                        "resolved_url": resolved_url,
                        "content_type": resolved["content_type"],
                        "size": size,
                    }

            if mode == "file":
                raise RuntimeError("No direct file response was captured for this URL.")

            current_url = page.url or args.url
            if mode == "auto":
                fallback_name = args.filename or "download"
                fallback_name = args.filename or sanitize(page.title() or "page")
                out_path = build_output_path(args.destination_dir, args.out, fallback_name, fallback_name, ".html")
                saved_path = save_html(page, out_path)
                return {
                    "status": "saved_html",
                    "path": str(saved_path),
                    "url": args.url,
                    "page_url": current_url,
                    "fallback_url": fallback_url,
                }

            out_path = build_output_path(args.destination_dir, args.out, args.filename or "link", "link", ".url")
            write_shortcut(out_path, current_url)
            return {"status": "saved_shortcut", "path": str(out_path), "url": current_url}
        finally:
            page.close()
    finally:
        browser.close()
        playwright.stop()


def read_spec(spec_path: str) -> List[Dict[str, Any]]:
    data = json.loads(Path(spec_path).read_text(encoding="utf-8"))
    if isinstance(data, dict):
        if isinstance(data.get("items"), list):
            return data["items"]
        if isinstance(data.get("downloads"), list):
            return data["downloads"]
    if isinstance(data, list):
        return data
    raise ValueError("Spec must be a JSON array or an object containing items/downloads.")


def cmd_batch(args) -> Dict[str, Any]:
    items = read_spec(args.spec)
    root_dir = Path(args.destination_dir) if args.destination_dir else None
    manifest_items = []

    for index, item in enumerate(items, start=1):
        url = item.get("url")
        if not url:
            manifest_items.append({"index": index, "status": "error", "error": "Missing url"})
            continue

        mode = (item.get("mode") or "auto").lower()
        destination_dir = item.get("destination_dir") or item.get("directory")
        if root_dir and destination_dir and not Path(destination_dir).is_absolute():
            destination_dir = str(root_dir / destination_dir)
        elif root_dir and not destination_dir:
            destination_dir = str(root_dir)

        out = item.get("out")
        if root_dir and out and not Path(out).is_absolute():
            out = str(root_dir / out)

        sub_args = argparse.Namespace(
            cdp=args.cdp,
            url=url,
            mode=mode,
            destination_dir=destination_dir,
            out=out,
            filename=item.get("filename"),
        )

        try:
            result = cmd_download(sub_args)
            result["index"] = index
        except Exception as exc:
            result = {
                "index": index,
                "status": "error",
                "url": url,
                "error": f"{type(exc).__name__}: {exc}",
            }
        manifest_items.append(result)

    manifest = {"count": len(manifest_items), "items": manifest_items}
    if args.manifest:
        write_text(Path(args.manifest), json.dumps(manifest, indent=2, ensure_ascii=False))
        manifest["manifest_path"] = str(Path(args.manifest))
    return manifest


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Authenticated Chromium browser helper for Codex PowerShell tools.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    extension_install = subparsers.add_parser("extension-install")
    extension_install.add_argument("--extensions-root", required=True)
    extension_install.add_argument("--browser", default="edge", choices=["edge", "chrome"])
    extension_install.add_argument("--name")
    extension_install.add_argument("--source-url")
    extension_install.add_argument("--package-path")
    extension_install.add_argument("--directory-path")
    extension_install.add_argument("--overwrite", action="store_true")

    extension_runtime_list = subparsers.add_parser("extension-runtime-list")
    extension_runtime_list.add_argument("--cdp", required=True)
    extension_runtime_list.add_argument("--browser", default="edge", choices=["edge", "chrome"])
    extension_runtime_list.add_argument("--user-data-dir")
    extension_runtime_list.add_argument("--profile-directory", default="Default")

    extension_open = subparsers.add_parser("extension-open")
    extension_open.add_argument("--cdp", required=True)
    extension_open.add_argument("--browser", default="edge", choices=["edge", "chrome"])
    extension_open.add_argument("--name")
    extension_open.add_argument("--extension-id")
    extension_open.add_argument("--page-path")
    extension_open.add_argument("--url")
    extension_open.add_argument("--user-data-dir")
    extension_open.add_argument("--profile-directory", default="Default")

    extension_click = subparsers.add_parser("extension-click")
    extension_click.add_argument("--cdp", required=True)
    extension_click.add_argument("--browser", default="edge", choices=["edge", "chrome"])
    extension_click.add_argument("--name")
    extension_click.add_argument("--extension-id")
    extension_click.add_argument("--page-path")
    extension_click.add_argument("--url")
    extension_click.add_argument("--selector")
    extension_click.add_argument("--text-contains")
    extension_click.add_argument("--timeout-ms", type=int, default=5000)
    extension_click.add_argument("--user-data-dir")
    extension_click.add_argument("--profile-directory", default="Default")

    links = subparsers.add_parser("links")
    links.add_argument("--cdp", required=True)
    links.add_argument("--url")
    links.add_argument("--page-url-contains")
    links.add_argument("--out")

    save_page = subparsers.add_parser("save-page")
    save_page.add_argument("--cdp", required=True)
    save_page.add_argument("--url")
    save_page.add_argument("--page-url-contains")
    save_page.add_argument("--destination-dir")
    save_page.add_argument("--out")
    save_page.add_argument("--filename")

    download = subparsers.add_parser("download")
    download.add_argument("--cdp", required=True)
    download.add_argument("--url", required=True)
    download.add_argument("--mode", default="auto", choices=["auto", "file", "page", "shortcut", "folder", "quiz"])
    download.add_argument("--destination-dir")
    download.add_argument("--out")
    download.add_argument("--filename")

    infer_spec_cmd = subparsers.add_parser("infer-spec")
    infer_spec_cmd.add_argument("--cdp", required=True)
    infer_spec_cmd.add_argument("--site", default="auto", choices=["auto", "generic", "moodle", "sharepoint", "panopto"])
    infer_spec_cmd.add_argument("--url")
    infer_spec_cmd.add_argument("--page-url-contains")
    infer_spec_cmd.add_argument("--out")
    infer_spec_cmd.add_argument("--limit", type=int)

    chatgpt_export = subparsers.add_parser("chatgpt-export")
    chatgpt_export.add_argument("--cdp", required=True)
    chatgpt_export.add_argument("--url", default="https://chatgpt.com/")
    chatgpt_export.add_argument("--page-url-contains")
    chatgpt_export.add_argument("--destination-dir", required=True)
    chatgpt_export.add_argument("--limit", type=int)
    chatgpt_export.add_argument("--save-all", action="store_true")
    chatgpt_export.add_argument("--topic-label")
    chatgpt_export.add_argument("--default-study-keywords", action="store_true")
    chatgpt_export.add_argument("--keyword", action="append")

    chatgpt_list = subparsers.add_parser("chatgpt-list")
    chatgpt_list.add_argument("--cdp", required=True)
    chatgpt_list.add_argument("--url", default="https://chatgpt.com/")
    chatgpt_list.add_argument("--page-url-contains")
    chatgpt_list.add_argument("--title-contains")
    chatgpt_list.add_argument("--limit", type=int)

    chatgpt_open = subparsers.add_parser("chatgpt-open")
    chatgpt_open.add_argument("--cdp", required=True)
    chatgpt_open.add_argument("--url", default="https://chatgpt.com/")
    chatgpt_open.add_argument("--page-url-contains")
    chatgpt_open.add_argument("--conversation-id")
    chatgpt_open.add_argument("--title-contains")
    chatgpt_open.add_argument("--new-chat", action="store_true")
    chatgpt_open.add_argument("--export-dir")

    chatgpt_save = subparsers.add_parser("chatgpt-save")
    chatgpt_save.add_argument("--cdp", required=True)
    chatgpt_save.add_argument("--url", default="https://chatgpt.com/")
    chatgpt_save.add_argument("--page-url-contains")
    chatgpt_save.add_argument("--conversation-id")
    chatgpt_save.add_argument("--title-contains")
    chatgpt_save.add_argument("--new-chat", action="store_true")
    chatgpt_save.add_argument("--destination-dir", required=True)

    chatgpt_delete = subparsers.add_parser("chatgpt-delete")
    chatgpt_delete.add_argument("--cdp", required=True)
    chatgpt_delete.add_argument("--url", default="https://chatgpt.com/")
    chatgpt_delete.add_argument("--page-url-contains")
    chatgpt_delete.add_argument("--conversation-id")
    chatgpt_delete.add_argument("--title-contains")
    chatgpt_delete.add_argument("--current-chat", action="store_true")
    chatgpt_delete.add_argument("--export-dir")
    chatgpt_delete.add_argument("--confirm-delete", action="store_true")

    chatgpt_ask = subparsers.add_parser("chatgpt-ask")
    chatgpt_ask.add_argument("--cdp", required=True)
    chatgpt_ask.add_argument("--url", default="https://chatgpt.com/")
    chatgpt_ask.add_argument("--page-url-contains")
    chatgpt_ask.add_argument("--conversation-id")
    chatgpt_ask.add_argument("--title-contains")
    chatgpt_ask.add_argument("--new-chat", action="store_true")
    chatgpt_ask.add_argument("--prompt")
    chatgpt_ask.add_argument("--prompt-file")
    chatgpt_ask.add_argument("--prompt-stdin", action="store_true")
    chatgpt_ask.add_argument("--destination-dir", required=True)
    chatgpt_ask.add_argument("--attachment", action="append")
    chatgpt_ask.add_argument("--export-history-before", action="store_true")
    chatgpt_ask.add_argument("--result-name")
    chatgpt_ask.add_argument("--timeout", type=int, default=300)
    chatgpt_ask.add_argument("--max-total-seconds", type=int, default=0)

    batch = subparsers.add_parser("batch")
    batch.add_argument("--cdp", required=True)
    batch.add_argument("--spec", required=True)
    batch.add_argument("--destination-dir")
    batch.add_argument("--manifest")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        if args.command == "extension-install":
            result = cmd_extension_install(args)
        elif args.command == "extension-runtime-list":
            result = cmd_extension_runtime_list(args)
        elif args.command == "extension-open":
            result = cmd_extension_open(args)
        elif args.command == "extension-click":
            result = cmd_extension_click(args)
        elif args.command == "links":
            result = cmd_links(args)
        elif args.command == "infer-spec":
            result = cmd_infer_spec(args)
        elif args.command == "save-page":
            result = cmd_save_page(args)
        elif args.command == "download":
            result = cmd_download(args)
        elif args.command == "chatgpt-list":
            result = cmd_chatgpt_list(args)
        elif args.command == "chatgpt-open":
            result = cmd_chatgpt_open(args)
        elif args.command == "chatgpt-save":
            result = cmd_chatgpt_save(args)
        elif args.command == "chatgpt-delete":
            result = cmd_chatgpt_delete(args)
        elif args.command == "chatgpt-ask":
            result = cmd_chatgpt_ask(args)
        elif args.command == "chatgpt-export":
            result = cmd_chatgpt_export(args)
        elif args.command == "batch":
            result = cmd_batch(args)
        else:
            raise RuntimeError(f"Unsupported command: {args.command}")
    except Exception as exc:
        print(json.dumps({"status": "error", "error": f"{type(exc).__name__}: {exc}"}, ensure_ascii=False))
        return 1

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
