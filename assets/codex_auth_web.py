import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
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


def write_shortcut(path: Path, url: str) -> None:
    write_text(path, f"[InternetShortcut]\nURL={url}\n")


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", (value or "").strip())


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
        if args.command == "links":
            result = cmd_links(args)
        elif args.command == "infer-spec":
            result = cmd_infer_spec(args)
        elif args.command == "save-page":
            result = cmd_save_page(args)
        elif args.command == "download":
            result = cmd_download(args)
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
