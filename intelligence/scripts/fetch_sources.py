#!/usr/bin/env python3
"""DIS: AI業界ソースからRSS/HTMLを取得しSQLiteに保存。標準ライブラリのみ使用。"""
import os
import re
import sqlite3
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from html.parser import HTMLParser
from urllib.error import URLError
from urllib.request import Request, urlopen

DB = os.path.expanduser("~/.claude/intelligence/dev.db")
TIMEOUT = 10
USER_AGENT = "DIS/1.0 (Claude Code Intelligence)"

# ソース定義: (名前, URL, タイプ)
SOURCES = [
    ("anthropic", "https://www.anthropic.com/news", "html"),
    ("openai", "https://openai.com/blog/rss.xml", "rss"),
    ("deepmind", "https://deepmind.google/blog/rss.xml", "rss"),
    ("cursor", "https://www.cursor.com/blog", "html"),
    ("devin", "https://www.cognition.ai/blog", "html"),
    ("xai", "https://x.ai/blog", "html"),
]


class TitleExtractor(HTMLParser):
    """HTMLからタイトルとリンクを抽出する簡易パーサー。"""

    def __init__(self):
        super().__init__()
        self.items = []
        self._in_title = False
        self._in_a = False
        self._current_href = ""
        self._current_text = ""
        self._meta_desc = ""

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        if tag == "a" and attrs_dict.get("href", "").startswith(("http", "/")):
            self._in_a = True
            self._current_href = attrs_dict.get("href", "")
            self._current_text = ""
        if tag == "meta" and attrs_dict.get("name") == "description":
            self._meta_desc = attrs_dict.get("content", "")[:500]

    def handle_endtag(self, tag):
        if tag == "a" and self._in_a:
            self._in_a = False
            text = self._current_text.strip()
            if text and len(text) > 10 and self._current_href:
                self.items.append((text[:200], self._current_href))

    def handle_data(self, data):
        if self._in_a:
            self._current_text += data


def fetch_url(url: str) -> str | None:
    """URLからコンテンツを取得。"""
    try:
        req = Request(url, headers={"User-Agent": USER_AGENT})
        with urlopen(req, timeout=TIMEOUT) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except (URLError, TimeoutError, OSError) as e:
        print(f"  SKIP {url}: {e}")
        return None


def parse_rss(content: str) -> list[tuple[str, str, str]]:
    """RSS XMLをパースして (title, url, summary) のリストを返す。"""
    items = []
    try:
        root = ET.fromstring(content)
        # Atom/RSS共通パース
        ns = {"atom": "http://www.w3.org/2005/Atom"}
        for item in root.iter("item"):
            title = (item.findtext("title") or "").strip()
            link = (item.findtext("link") or "").strip()
            desc = (item.findtext("description") or "")[:500]
            if title and link:
                items.append((title, link, desc))
        for entry in root.iter("{http://www.w3.org/2005/Atom}entry"):
            title = (entry.findtext("{http://www.w3.org/2005/Atom}title") or "").strip()
            link_el = entry.find("{http://www.w3.org/2005/Atom}link")
            link = link_el.get("href", "") if link_el is not None else ""
            summary = (entry.findtext("{http://www.w3.org/2005/Atom}summary") or "")[:500]
            if title and link:
                items.append((title, link, summary))
    except ET.ParseError:
        pass
    return items


def parse_html(content: str, base_url: str) -> list[tuple[str, str, str]]:
    """HTMLからブログ記事リンクを抽出。"""
    parser = TitleExtractor()
    try:
        parser.feed(content)
    except Exception:
        return []

    items = []
    seen_urls = set()
    for text, href in parser.items:
        # 相対URLを絶対URLに変換
        if href.startswith("/"):
            from urllib.parse import urlparse
            parsed = urlparse(base_url)
            href = f"{parsed.scheme}://{parsed.netloc}{href}"
        if href in seen_urls:
            continue
        seen_urls.add(href)
        # blogっぽいURLのみ採用 (news, blog, post等)
        if re.search(r"blog|post|article|/news/|update|changelog", href, re.I):
            items.append((text, href, parser._meta_desc))

    return items[:20]  # 最大20件


def fetch_all():
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    now = datetime.utcnow().isoformat()
    total_new = 0

    for source_name, url, source_type in SOURCES:
        print(f"Fetching {source_name} ({url})...")
        content = fetch_url(url)
        if not content:
            continue

        if source_type == "rss":
            items = parse_rss(content)
        else:
            items = parse_html(content, url)

        new_count = 0
        for title, link, summary in items:
            try:
                cur.execute(
                    """INSERT OR IGNORE INTO industry_feeds(source, title, url, summary, fetched_at)
                       VALUES(?, ?, ?, ?, ?)""",
                    (source_name, title[:200], link, summary[:500], now),
                )
                if cur.rowcount > 0:
                    new_count += 1
            except sqlite3.IntegrityError:
                pass

        total_new += new_count
        print(f"  → {len(items)} found, {new_count} new")

    # 90日以上古い分析済みエントリを削除
    cur.execute("DELETE FROM industry_feeds WHERE analyzed = 1 AND ts < datetime('now', '-90 days')")
    cleaned = cur.rowcount

    conn.commit()
    conn.close()
    print(f"\nTotal: {total_new} new entries added, {cleaned} old entries cleaned")


if __name__ == "__main__":
    fetch_all()
