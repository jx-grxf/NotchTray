#!/usr/bin/env python3
"""Insert (or replace) one release in appcast.xml.

The feed accumulates rather than being regenerated: Sparkle picks the best
item it is allowed to see, so older entries are what let a user who skipped
several versions still find a valid update, and what makes a beta subscriber
fall back to the newest stable when no prerelease is pending.

Re-running for a version already in the feed replaces that entry, so a
re-published release does not leave a stale duplicate behind.
"""

import html
import os
import re
import sys
from email.utils import format_datetime
from datetime import datetime, timezone
from xml.etree import ElementTree

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ElementTree.register_namespace("sparkle", SPARKLE_NS)

APPCAST = "appcast.xml"

EMPTY_FEED = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="{SPARKLE_NS}">
  <channel>
    <title>{{app_name}}</title>
    <link>https://github.com/jx-grxf/NotchTray</link>
    <description>{{app_name}} update feed</description>
    <language>en</language>
  </channel>
</rss>
"""


def markdown_to_html(path):
    """Render the release notes subset actually used: headings, bullets, code."""
    if not path or not os.path.exists(path):
        return ""

    # The notes are hard-wrapped, so a paragraph or bullet spans several
    # source lines. Reflow first: a block ends at a blank line, a heading, or
    # the start of the next bullet — not at every newline.
    blocks = []
    for raw in open(path, encoding="utf-8").read().splitlines():
        line = raw.rstrip()
        stripped = line.strip()

        if not stripped:
            blocks.append(None)
            continue

        heading = re.match(r"^#{2,3}\s+(.*)$", stripped)
        bullet = re.match(r"^[-*]\s+(.*)$", stripped)

        if heading:
            blocks.append(("h", heading.group(1)))
        elif bullet:
            blocks.append(("li", bullet.group(1)))
        elif blocks and blocks[-1] is not None and blocks[-1][0] in ("li", "p"):
            kind, text = blocks[-1]
            blocks[-1] = (kind, f"{text} {stripped}")
        else:
            blocks.append(("p", stripped))

    out, in_list = [], False
    for block in blocks:
        if block is None:
            continue
        kind, text = block
        if kind != "li" and in_list:
            out.append("</ul>")
            in_list = False
        if kind == "h":
            out.append(f"<h3>{inline(text)}</h3>")
        elif kind == "li":
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(text)}</li>")
        else:
            out.append(f"<p>{inline(text)}</p>")

    if in_list:
        out.append("</ul>")
    return "".join(out)


def inline(text):
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"`(.+?)`", r"<code>\1</code>", escaped)
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)


def main():
    app_name = os.environ["APP_NAME"]
    version = os.environ["VERSION"]
    build = os.environ["BUILD"]
    channel = os.environ["CHANNEL"]

    if not os.path.exists(APPCAST):
        with open(APPCAST, "w", encoding="utf-8") as handle:
            handle.write(EMPTY_FEED.format(app_name=app_name))

    tree = ElementTree.parse(APPCAST)
    channel_element = tree.getroot().find("channel")

    # Drop any existing entry for this version so re-publishing is idempotent.
    for item in channel_element.findall("item"):
        existing = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
        if existing is not None and existing.text == version:
            channel_element.remove(item)

    item = ElementTree.Element("item")
    ElementTree.SubElement(item, "title").text = f"{app_name} {version}"

    notes = markdown_to_html(os.environ.get("NOTES_FILE"))
    if notes:
        ElementTree.SubElement(item, "description").text = notes

    if channel != "stable":
        ElementTree.SubElement(item, f"{{{SPARKLE_NS}}}channel").text = channel

    ElementTree.SubElement(item, f"{{{SPARKLE_NS}}}version").text = build
    ElementTree.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = version
    ElementTree.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion").text = "14.0"
    ElementTree.SubElement(item, "pubDate").text = format_datetime(
        datetime.now(timezone.utc)
    )

    enclosure = ElementTree.SubElement(item, "enclosure")
    enclosure.set("url", os.environ["DOWNLOAD_URL"])
    enclosure.set("length", os.environ["LENGTH"])
    enclosure.set("type", "application/octet-stream")
    enclosure.set(f"{{{SPARKLE_NS}}}edSignature", os.environ["ED_SIGNATURE"])

    # Newest first: Sparkle does not require it, but it keeps the file readable.
    channel_element.insert(4, item)

    ElementTree.indent(tree, space="  ")
    tree.write(APPCAST, encoding="utf-8", xml_declaration=True)

    # CDATA is not something ElementTree can emit, and Sparkle expects the
    # description to be HTML rather than escaped text.
    text = open(APPCAST, encoding="utf-8").read()
    text = re.sub(
        r"<description>(.*?)</description>",
        lambda m: "<description><![CDATA[%s]]></description>"
        % html.unescape(m.group(1)),
        text,
        flags=re.DOTALL,
    )
    open(APPCAST, "w", encoding="utf-8").write(text)


if __name__ == "__main__":
    sys.exit(main())
