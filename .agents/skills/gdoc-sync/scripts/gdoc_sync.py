#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["markdown-it-py>=3"]
# ///
"""Plan a comment-preserving sync of a local markdown file into one Google Doc tab.

Prose edits become Docs API requests (small insert/delete ranges, so comment
anchors survive). Code blocks, images, tables that change shape, and anything
structural become "paste" groups: the planned requests delete the old range and
leave a marker paragraph that the agent replaces with Docs' Paste from Markdown.

Subcommands:
  init   MD URL            write the sidecar that links MD to a doc tab
  plan   MD DOC_JSON       diff MD against the doc tab JSON and write a plan
  accept MD                record MD as the last-synced base (after a clean sync)
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import secrets
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

from markdown_it import MarkdownIt

CODE_MARK = "\ue907"
OBJ = "\ufffc"
MONO_FONTS = {"roboto mono", "courier new", "consolas", "source code pro", "courier", "menlo", "monaco"}
CODE_COLOR = {"red": 0.09411765, "green": 0.5019608, "blue": 0.21960784}
LINK_COLOR = {"red": 0.06666667, "green": 0.33333334, "blue": 0.8}
PROSE = {"p", "h", "li"}

# ---------------------------------------------------------------- sidecar


def sidecar_paths(md: Path) -> tuple[Path, Path]:
    return md.with_name(f".{md.name}.gdoc.json"), md.with_name(f".{md.name}.gdoc-base.md")


def parse_doc_url(url: str) -> tuple[str, str | None]:
    m = re.search(r"/document/d/([A-Za-z0-9_-]+)", url)
    if not m:
        sys.exit(f"not a Google Doc URL: {url}")
    t = re.search(r"[?&]tab=([A-Za-z0-9._-]+)", url)
    return m.group(1), t.group(1) if t else None


# ---------------------------------------------------------------- blocks


Seg = tuple[str, frozenset, str | None]  # text, attrs {b,i,s,code}, link url


@dataclass
class Block:
    kind: str  # p h li code table img hr
    level: int = 0  # heading level or list nesting
    segs: list[Seg] = field(default_factory=list)
    code: str = ""
    src: str = ""  # image src
    cells: list[list[list[Seg]]] = field(default_factory=list)
    lines: tuple[int, int] = (0, 0)  # md source line range
    # doc-only
    start: int = 0
    end: int = 0
    chars: list[int] = field(default_factory=list)
    has_objects: bool = False
    cell_info: list[list[dict]] = field(default_factory=list)

    @property
    def text(self) -> str:
        if self.kind == "code":
            return self.code
        if self.kind == "table":
            return " | ".join(seg_text(c) for row in self.cells for c in row)
        return seg_text(self.segs)

    def sig(self) -> tuple:
        if self.kind in PROSE:
            return (self.kind, self.level, norm(self.text))
        if self.kind == "code":
            return ("code", self.code.strip())
        if self.kind == "table":
            return ("table", tuple(tuple(norm(seg_text(c)) for c in row) for row in self.cells))
        return (self.kind,)

    def canon(self) -> tuple:
        if self.kind in PROSE:
            return (self.kind, self.level, canon_segs(self.segs, drop_bold=self.kind == "h"))
        if self.kind == "table":
            return (
                "table",
                tuple(tuple(canon_segs(c, drop_bold=r == 0) for c in row) for r, row in enumerate(self.cells)),
            )
        if self.kind == "img":
            return ("img", self.src)
        return self.sig()


def seg_text(segs: list[Seg]) -> str:
    return "".join(s[0] for s in segs)


def norm(t: str) -> str:
    return re.sub(r"\s+", " ", t).strip()


def canon_segs(segs: list[Seg], drop_bold: bool = False) -> tuple:
    out: list[list] = []
    for text, attrs, link in segs:
        a = set(attrs)
        if drop_bold:
            a.discard("b")
        if "code" in a:
            a -= {"b", "i"}
        key = (frozenset(a), link)
        if out and out[-1][1] == key:
            out[-1][0] += text
        else:
            out.append([text, key])
    if out:
        out[0][0] = out[0][0].lstrip()
        out[-1][0] = out[-1][0].rstrip()
    return tuple((t, k) for t, k in out if t)


# ---------------------------------------------------------------- markdown


def md_blocks(src: str) -> list[Block]:
    md = MarkdownIt("commonmark").enable(["table", "strikethrough"])
    toks = md.parse(src)
    blocks: list[Block] = []
    list_depth = 0
    item_first_para: list[bool] = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.type in ("bullet_list_open", "ordered_list_open"):
            list_depth += 1
        elif t.type in ("bullet_list_close", "ordered_list_close"):
            list_depth -= 1
        elif t.type == "list_item_open":
            item_first_para.append(True)
        elif t.type == "list_item_close":
            item_first_para.pop()
        elif t.type == "heading_open":
            blocks.append(Block("h", int(t.tag[1]), inline_segs(toks[i + 1].children), lines=tuple(t.map)))
            i += 2
        elif t.type == "paragraph_open":
            children = toks[i + 1].children or []
            real = [c for c in children if not (c.type == "text" and not c.content.strip()) and c.type != "softbreak"]
            lines = tuple(t.map)
            if len(real) == 1 and real[0].type == "image":
                blocks.append(Block("img", src=real[0].attrGet("src") or "", lines=lines))
            elif item_first_para and item_first_para[-1]:
                item_first_para[-1] = False
                blocks.append(Block("li", list_depth - 1, inline_segs(children), lines=lines))
            else:
                blocks.append(Block("p", 0, inline_segs(children), lines=lines))
            i += 2
        elif t.type in ("fence", "code_block"):
            blocks.append(Block("code", code=t.content, lines=tuple(t.map)))
        elif t.type == "hr":
            blocks.append(Block("hr", lines=tuple(t.map)))
        elif t.type == "table_open":
            j, rows, row = i + 1, [], None
            while toks[j].type != "table_close":
                tj = toks[j]
                if tj.type == "tr_open":
                    row = []
                elif tj.type == "tr_close":
                    rows.append(row)
                elif tj.type == "inline":
                    row.append(inline_segs(tj.children))
                j += 1
            blocks.append(Block("table", cells=rows, lines=tuple(t.map)))
            i = j
        elif t.type == "html_block":
            print(f"warning: raw HTML block at line {t.map[0] + 1} is not synced", file=sys.stderr)
        i += 1
    return blocks


def inline_segs(children) -> list[Seg]:
    segs: list[Seg] = []
    attrs: set[str] = set()
    link: str | None = None
    for c in children or []:
        if c.type == "text" or c.type == "html_inline":
            segs.append((c.content, frozenset(attrs), link))
        elif c.type == "code_inline":
            segs.append((c.content, frozenset(attrs | {"code"}), link))
        elif c.type == "softbreak":
            segs.append((" ", frozenset(attrs), link))
        elif c.type == "hardbreak":
            segs.append(("\u000b", frozenset(attrs), link))
        elif c.type in ("strong_open", "em_open", "s_open"):
            attrs.add({"strong_open": "b", "em_open": "i", "s_open": "s"}[c.type])
        elif c.type in ("strong_close", "em_close", "s_close"):
            attrs.discard({"strong_close": "b", "em_close": "i", "s_close": "s"}[c.type])
        elif c.type == "link_open":
            link = c.attrGet("href")
        elif c.type == "link_close":
            link = None
        elif c.type == "image":
            segs.append((c.content or "", frozenset(attrs), link))
    return segs


# ---------------------------------------------------------------- doc


def run_attrs(ts: dict) -> tuple[frozenset, str | None]:
    a = set()
    if ts.get("bold"):
        a.add("b")
    if ts.get("italic"):
        a.add("i")
    if ts.get("strikethrough"):
        a.add("s")
    ff = ts.get("weightedFontFamily", {}).get("fontFamily", "")
    if ff.lower() in MONO_FONTS:
        a.add("code")
    return frozenset(a), (ts.get("link") or {}).get("url")


def para_parts(p: dict, skip_code_mark: bool = True):
    """Return (segs, chars, has_objects, n_marks, mark_positions)."""
    segs: list[Seg] = []
    chars: list[int] = []
    objects = False
    marks: list[int] = []
    for e in p["elements"]:
        if "textRun" in e:
            tr = e["textRun"]
            attrs, link = run_attrs(tr.get("textStyle", {}))
            buf = []
            for k, ch in enumerate(tr["content"]):
                idx = e["startIndex"] + k
                if ch == CODE_MARK:
                    marks.append(idx)
                    continue
                if ch == "\n":
                    continue
                buf.append(ch)
                chars.append(idx)
            if buf:
                segs.append(("".join(buf), attrs, link))
        elif "inlineObjectElement" in e:
            objects = True
        elif "horizontalRule" in e or "pageBreak" in e:
            pass
        else:
            objects = True
    return segs, chars, objects, marks


def doc_body(doc: dict, tab_id: str | None) -> list[dict]:
    """Accept either a single-tab payload (natoma get_doc_content with tabId) or a full includeTabsContent doc."""
    if "body" in doc:
        return doc["body"]["content"]
    for t in doc.get("tabs", []):
        stack = [t]
        while stack:
            cur = stack.pop()
            if cur.get("tabProperties", {}).get("tabId") == tab_id:
                return cur["documentTab"]["body"]["content"]
            stack.extend(cur.get("childTabs", []))
    sys.exit("could not find tab body in doc JSON")


def doc_blocks(content: list[dict]) -> tuple[list[Block], int]:
    blocks: list[Block] = []
    body_end = content[-1]["endIndex"] if content else 1
    code: Block | None = None
    for el in content:
        if "paragraph" in el:
            p = el["paragraph"]
            segs, chars, objects, marks = para_parts(p)
            hr = any("horizontalRule" in e for e in p["elements"])
            st = p.get("paragraphStyle", {}).get("namedStyleType", "NORMAL_TEXT")
            if code is None and marks and marks[0] == el["startIndex"]:
                code = Block("code", start=marks[0])
                code.code = seg_text(segs) + "\n"
                if len(marks) > 1:  # single-line block closed in the same paragraph
                    code.end = marks[1] + 1
                    blocks.append(code)
                    code = None
                continue
            if code is not None:
                if marks and marks[0] == el["startIndex"]:
                    code.end = marks[0] + 1
                    blocks.append(code)
                    code = None
                else:
                    code.code += seg_text(segs) + "\n"
                    continue
            if hr and not seg_text(segs).strip():
                blocks.append(Block("hr", start=el["startIndex"], end=el["endIndex"]))
                continue
            if objects and not seg_text(segs).strip():
                blocks.append(Block("img", start=el["startIndex"], end=el["endIndex"]))
                continue
            if not seg_text(segs).strip():
                continue
            if "bullet" in p:
                kind, level = "li", p["bullet"].get("nestingLevel", 0)
            elif st.startswith("HEADING_"):
                kind, level = "h", int(st.split("_")[1])
            elif st == "TITLE":
                kind, level = "h", 1
            else:
                kind, level = "p", 0
            blocks.append(
                Block(kind, level, segs, start=el["startIndex"], end=el["endIndex"], chars=chars, has_objects=objects)
            )
        elif "table" in el:
            rows, info = [], []
            for tr in el["table"]["tableRows"]:
                row, irow = [], []
                for cell in tr["tableCells"]:
                    paras = [c["paragraph"] for c in cell["content"] if "paragraph" in c]
                    segs, chars, objects, _ = para_parts(paras[0]) if paras else ([], [], False, [])
                    row.append(segs)
                    first = cell["content"][0]
                    irow.append(
                        {
                            "chars": chars,
                            "pend": first["endIndex"],
                            "multi": len(paras) > 1 or objects,
                        }
                    )
                rows.append(row)
                info.append(irow)
            blocks.append(Block("table", cells=rows, cell_info=info, start=el["startIndex"], end=el["endIndex"]))
    return blocks, body_end


# ---------------------------------------------------------------- alignment


def family(b: Block) -> str:
    return "prose" if b.kind in PROSE else b.kind


def similar(a: Block, b: Block) -> float:
    if family(a) != family(b):
        return 0.0
    if a.kind in ("img", "hr"):
        return 1.0
    return difflib.SequenceMatcher(None, norm(a.text), norm(b.text), autojunk=False).ratio()


def align(old: list[Block], new: list[Block]) -> list[tuple[int | None, int | None]]:
    """Monotonic alignment of block lists. Returns (old_idx, new_idx) pairs in order."""
    sm = difflib.SequenceMatcher(None, [b.sig() for b in old], [b.sig() for b in new], autojunk=False)
    out: list[tuple[int | None, int | None]] = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            out.extend(zip(range(i1, i2), range(j1, j2)))
            continue
        oi = i1
        for j in range(j1, j2):
            best, best_i = 0.5, None
            for k in range(oi, i2):
                s = similar(old[k], new[j])
                if s > best:
                    best, best_i = s, k
            if best_i is None:
                out.append((None, j))
            else:
                out.extend((k, None) for k in range(oi, best_i))
                out.append((best_i, j))
                oi = best_i + 1
        out.extend((k, None) for k in range(oi, i2))
    return out


# ---------------------------------------------------------------- request builders


def tokens(s: str) -> list[str]:
    return re.findall(r"\w+|\s+|[^\w\s]", s)


def text_edit_requests(chars: list[int], end_idx: int, old: str, new: str, tab: str) -> list[dict]:
    """Minimal insert/delete requests turning old into new. chars[k] is the doc index of old[k]."""
    a, b = tokens(old), tokens(new)
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    offs = [0]
    for t in a:
        offs.append(offs[-1] + len(t))
    reqs: list[dict] = []
    for tag, i1, i2, j1, j2 in reversed(sm.get_opcodes()):
        if tag == "equal":
            continue
        c1, c2 = offs[i1], offs[i2]
        at = chars[c1] if c1 < len(chars) else end_idx
        if c2 > c1:
            reqs.append(
                {"deleteContentRange": {"range": {"startIndex": chars[c1], "endIndex": chars[c2 - 1] + 1, "tabId": tab}}}
            )
        ins = "".join(b[j1:j2])
        if ins:
            reqs.append({"insertText": {"location": {"index": at, "tabId": tab}, "text": ins}})
    return reqs


def style_requests(start: int, segs: list[Seg], tab: str, keep_bold: bool = False) -> list[dict]:
    text = seg_text(segs)
    if not text:
        return []
    fields = "italic,strikethrough,link,underline,foregroundColor,weightedFontFamily,fontSize"
    if not keep_bold:
        fields = "bold," + fields
    reqs = [
        {
            "updateTextStyle": {
                "range": {"startIndex": start, "endIndex": start + len(text), "tabId": tab},
                "textStyle": {},
                "fields": fields,
            }
        }
    ]
    pos = start
    for t, attrs, link in segs:
        rng = {"startIndex": pos, "endIndex": pos + len(t), "tabId": tab}
        pos += len(t)
        style, f = {}, []
        if "b" in attrs and not keep_bold:
            style["bold"], f = True, f + ["bold"]
        if "i" in attrs:
            style["italic"], f = True, f + ["italic"]
        if "s" in attrs:
            style["strikethrough"], f = True, f + ["strikethrough"]
        if "code" in attrs:
            style["weightedFontFamily"] = {"fontFamily": "Roboto Mono", "weight": 400}
            style["foregroundColor"] = {"color": {"rgbColor": CODE_COLOR}}
            f += ["weightedFontFamily", "foregroundColor"]
        if link:
            style["link"] = {"url": link}
            style["underline"] = True
            style["foregroundColor"] = {"color": {"rgbColor": LINK_COLOR}}
            f += ["link", "underline", "foregroundColor"]
        if f and t.strip():
            reqs.append({"updateTextStyle": {"range": rng, "textStyle": style, "fields": ",".join(sorted(set(f)))}})
    return reqs


def named_style(b: Block) -> str:
    return f"HEADING_{b.level}" if b.kind == "h" else "NORMAL_TEXT"


def strip_segs(segs: list[Seg]) -> list[Seg]:
    """Trim leading/trailing whitespace across segments (doc paragraphs never carry it from md)."""
    segs = [list(s) for s in segs if s[0]]
    if segs:
        segs[0][0] = segs[0][0].lstrip()
        segs[-1][0] = segs[-1][0].rstrip()
    return [tuple(s) for s in segs if s[0]]


def paragraph_edit(d: Block, n: Block, tab: str) -> list[dict]:
    new_segs = strip_segs(n.segs)
    old_text, new_text = seg_text(d.segs), seg_text(new_segs)
    first = d.chars[0] if d.chars else d.start
    reqs = text_edit_requests(d.chars, d.end - 1, old_text, new_text, tab)
    if (d.kind, d.level) != (n.kind, n.level) and n.kind != "li":
        reqs.append(
            {
                "updateParagraphStyle": {
                    "range": {"startIndex": first, "endIndex": first + max(len(new_text), 1), "tabId": tab},
                    "paragraphStyle": {"namedStyleType": named_style(n)},
                    "fields": "namedStyleType",
                }
            }
        )
    if canon_segs(d.segs, n.kind == "h") != canon_segs(new_segs, n.kind == "h") or reqs:
        reqs += style_requests(first, new_segs, tab, keep_bold=n.kind == "h")
    return reqs


def table_edit(d: Block, n: Block, tab: str) -> list[dict] | None:
    if [len(r) for r in d.cells] != [len(r) for r in n.cells]:
        return None
    reqs: list[dict] = []
    for r in range(len(n.cells) - 1, -1, -1):
        for c in range(len(n.cells[r]) - 1, -1, -1):
            info = d.cell_info[r][c]
            old, new = d.cells[r][c], strip_segs(n.cells[r][c])
            hdr = r == 0
            if canon_segs(old, hdr) == canon_segs(new, hdr):
                continue
            if info["multi"]:
                return None
            first = info["chars"][0] if info["chars"] else info["pend"] - 1
            reqs += text_edit_requests(info["chars"], info["pend"] - 1, seg_text(old), seg_text(new), tab)
            reqs += style_requests(first, new, tab, keep_bold=hdr)
    return reqs


# ---------------------------------------------------------------- plan


def plan(md_path: Path, doc_json: Path, out_dir: Path, force: bool, verify: bool = False) -> dict:
    side, base_path = sidecar_paths(md_path)
    if not side.exists():
        sys.exit(f"no sidecar {side}; run: gdoc_sync.py init {md_path} <doc-tab-url>")
    cfg = json.loads(side.read_text())
    tab = cfg["tabId"]
    src = md_path.read_text()
    src_lines = src.splitlines(keepends=True)
    new = md_blocks(src)
    base = md_blocks(base_path.read_text()) if base_path.exists() else None
    doc = json.loads(doc_json.read_text())
    content = doc_body(doc, tab)
    docb, body_end = doc_blocks(content)

    base_for_new: dict[int, Block] = {}
    base_sigs: set = set()
    if base is not None:
        for bi, ni in align(base, new):
            if bi is not None and ni is not None:
                base_for_new[ni] = base[bi]
        base_sigs = {b.sig() for b in base}

    warnings: list[str] = []
    # items in final (new) order: (action, doc_block|None, new_block|None)
    items: list[tuple[str, Block | None, Block | None]] = []
    for di, ni in align(docb, new):
        d = docb[di] if di is not None else None
        n = new[ni] if ni is not None else None
        b = base_for_new.get(ni) if ni is not None else None
        if d is not None and n is not None:
            if n.kind == "img":
                changed = not verify and b is not None and b.src != n.src
            else:
                changed = d.canon() != n.canon()
            if not changed:
                items.append(("keep", d, n))
                continue
            if b is not None and b.canon() == n.canon() and not force:
                warnings.append(f"doc edited remotely, markdown unchanged (pull into md?): {d.text[:120]!r}")
                items.append(("keep", d, n))
                continue
            if b is not None and b.canon() != d.canon() and n.kind != "img" and not force:
                warnings.append(f"conflict, both sides changed (skipped; --force to overwrite doc): {d.text[:120]!r}")
                items.append(("keep", d, n))
                continue
            if d.kind in PROSE and n.kind in PROSE and not d.has_objects:
                if (d.kind == "li") == (n.kind == "li") and (d.kind != "li" or d.level == n.level):
                    items.append(("edit", d, n))
                    continue
            if d.kind == "table" and n.kind == "table":
                if table_edit(d, n, tab) is not None:
                    items.append(("edit", d, n))
                    continue
            if d.has_objects:
                warnings.append(f"paragraph has smart chips/objects; replacing it drops them: {d.text[:120]!r}")
            items.append(("paste", d, n))
        elif n is not None:
            if b is not None and not force:
                warnings.append(f"block deleted in doc remotely (kept deleted): {n.text[:120]!r}")
                continue
            items.append(("insert", None, n))
        else:
            if base is not None and d.sig() not in base_sigs and not force:
                warnings.append(f"block added in doc remotely (left in place, pull into md?): {d.text[:120]!r}")
                items.append(("keep", d, None))
                continue
            items.append(("delete", d, None))

    # Decide insert strategy: API insert after a prose neighbour of compatible kind, else paste.
    prev_doc: Block | None = None
    for k, (act, d, n) in enumerate(items):
        if act == "insert":
            ok = (
                prev_doc is not None
                and prev_doc.kind in PROSE
                and not prev_doc.has_objects
                and n.kind in PROSE
                and (
                    (n.kind == "li" and prev_doc.kind == "li" and prev_doc.level == n.level)
                    or (n.kind in ("p", "h") and prev_doc.kind in ("p", "h"))
                )
            )
            items[k] = ("api_insert" if ok else "paste", prev_doc if ok else None, n)
        if d is not None and act in ("keep", "edit"):
            prev_doc = d

    # Group runs of paste/delete into marker groups.
    groups: list[dict] = []
    edits: list[tuple[int, list[dict]]] = []  # (doc anchor index, requests) applied bottom-up
    k = 0
    api_inserts: dict[int, list[Block]] = {}
    while k < len(items):
        act, d, n = items[k]
        if act in ("paste", "delete"):
            run = []
            while k < len(items) and items[k][0] in ("paste", "delete"):
                run.append(items[k])
                k += 1
            removed = [x[1] for x in run if x[1] is not None]
            added = [x[2] for x in run if x[2] is not None]
            nxt = next((x[1] for x in items[k:] if x[1] is not None and x[0] in ("keep", "edit")), None)
            if removed:
                s, e = removed[0].start, removed[-1].end
            else:
                s = e = nxt.start if nxt else body_end - 1
            groups.append({"start": s, "end": e, "added": added, "removed": removed})
            continue
        if act == "edit":
            reqs = paragraph_edit(d, n, tab) if d.kind in PROSE else table_edit(d, n, tab)
            if reqs:
                edits.append((d.start, reqs))
        elif act == "api_insert":
            api_inserts.setdefault(id(d), [d]).append(n)
        k += 1

    for group in api_inserts.values():
        prev, news = group[0], group[1:]
        at = prev.end - 1
        reqs: list[dict] = []
        for n in reversed(news):
            segs = strip_segs(n.segs)
            text = seg_text(segs)
            reqs.append({"insertText": {"location": {"index": at, "tabId": tab}, "text": "\n" + text}})
            reqs.append(
                {
                    "updateParagraphStyle": {
                        "range": {"startIndex": at + 1, "endIndex": at + 1 + len(text), "tabId": tab},
                        "paragraphStyle": {"namedStyleType": named_style(n)},
                        "fields": "namedStyleType",
                    }
                }
            )
            reqs += style_requests(at + 1, segs, tab, keep_bold=n.kind == "h")
        # Anchor just after prev's start so these run before any edit of prev itself.
        edits.append((prev.end - 0.5, reqs))

    out_dir.mkdir(parents=True, exist_ok=True)
    for f in out_dir.glob("paste-*.md"):
        f.unlink()
    pastes = []
    for gi, g in enumerate(groups):
        if not g["added"]:
            s, e = g["start"], min(g["end"], body_end - 1)
            if e > s:
                edits.append((s, [{"deleteContentRange": {"range": {"startIndex": s, "endIndex": e, "tabId": tab}}}]))
            continue
        marker = f"GDOCSYNC{gi + 1}X{secrets.token_hex(3).upper()}"
        lo = min(b.lines[0] for b in g["added"])
        hi = max(b.lines[1] for b in g["added"])
        snippet = "".join(src_lines[lo:hi]).strip("\n") + "\n"
        path = out_dir / f"paste-{gi + 1}.md"
        path.write_text(snippet)
        s, e = g["start"], min(g["end"], body_end - 1)
        reqs = []
        if e > s:
            reqs.append({"deleteContentRange": {"range": {"startIndex": s, "endIndex": e, "tabId": tab}}})
        reqs.append({"insertText": {"location": {"index": s, "tabId": tab}, "text": marker + "\n"}})
        reqs.append(
            {
                "updateParagraphStyle": {
                    "range": {"startIndex": s, "endIndex": s + len(marker), "tabId": tab},
                    "paragraphStyle": {"namedStyleType": "NORMAL_TEXT"},
                    "fields": "namedStyleType,shading,indentStart,indentFirstLine,indentEnd",
                }
            }
        )
        reqs.append({"deleteParagraphBullets": {"range": {"startIndex": s, "endIndex": s + len(marker), "tabId": tab}}})
        reqs += style_requests(s, [(marker, frozenset(), None)], tab)
        edits.append((s, reqs))
        pastes.append(
            {
                "marker": marker,
                "file": str(path),
                "lines": f"{lo + 1}-{hi}",
                "replaces": [b.text[:80] for b in g["removed"]],
            }
        )

    edits.sort(key=lambda x: x[0], reverse=True)
    requests = [r for _, rs in edits for r in rs]
    external_links = any("link" in r.get("updateTextStyle", {}).get("textStyle", {}) for r in requests)
    n_del = sum(1 for r in requests if "deleteContentRange" in r)
    result = {
        "documentId": cfg["documentId"],
        "tabId": tab,
        "requests": requests,
        "pastes": pastes,
        "warnings": warnings,
        "needs": {"confirmExternalLink": external_links, "confirmBulkDelete": n_del > 20},
        "summary": {
            "api_edits": sum(1 for a, *_ in items if a == "edit"),
            "api_inserts": sum(1 for a, *_ in items if a == "api_insert"),
            "deletes": sum(1 for a, *_ in items if a == "delete"),
            "paste_groups": len(pastes),
            "requests": len(requests),
            "first_sync": base is None,
        },
    }
    (out_dir / "plan.json").write_text(json.dumps(result, indent=1))
    (out_dir / "requests.json").write_text(json.dumps(requests))
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_init = sub.add_parser("init")
    p_init.add_argument("md", type=Path)
    p_init.add_argument("url")
    p_plan = sub.add_parser("plan")
    p_plan.add_argument("md", type=Path)
    p_plan.add_argument("doc_json", type=Path)
    p_plan.add_argument("--out", type=Path, help="default: ~/CWS-outbox/gdoc-sync/<md stem>")
    p_plan.add_argument("--force", action="store_true", help="overwrite remote doc edits and conflicts")
    p_plan.add_argument(
        "--verify",
        action="store_true",
        help="post-sync check: images can't be compared, so treat them as synced; exit 1 if anything remains",
    )
    p_acc = sub.add_parser("accept")
    p_acc.add_argument("md", type=Path)
    args = ap.parse_args()

    if args.cmd == "init":
        doc_id, tab = parse_doc_url(args.url)
        if not tab:
            sys.exit("URL has no ?tab=...; open the target tab in Docs and copy its URL")
        side, _ = sidecar_paths(args.md)
        side.write_text(json.dumps({"documentId": doc_id, "tabId": tab, "url": args.url}, indent=1) + "\n")
        print(side)
    elif args.cmd == "plan":
        out = args.out or Path.home() / "CWS-outbox" / "gdoc-sync" / args.md.stem
        res = plan(args.md, args.doc_json, out, args.force, args.verify)
        print(json.dumps({k: res[k] for k in ("summary", "needs", "pastes", "warnings")}, indent=1))
        print(f"plan: {out / 'plan.json'}  requests: {out / 'requests.json'}", file=sys.stderr)
        if args.verify:
            leftover = res["requests"] or res["pastes"]
            print("verify: CLEAN" if not leftover else "verify: CHANGES REMAIN", file=sys.stderr)
            sys.exit(1 if leftover else 0)
    elif args.cmd == "accept":
        _, base = sidecar_paths(args.md)
        shutil.copyfile(args.md, base)
        print(base)


if __name__ == "__main__":
    main()
