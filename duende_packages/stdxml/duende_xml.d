module duende_packages.stdxml.duende_xml;

import std.algorithm;
import std.array;
import std.algorithm.sorting : sort;
import std.conv;
import std.string;
import dxml.dom; // parseDOM
import dxml.writer; // XML writer

// Lightweight XML Node wrapper suitable for Duende (string-based)
struct XmlNode {
    string name;
    string[string] attributes;
    string text; // concatenated text within this element (no children tags)
    XmlNode[] children;
}

// Internal: convert dxml.dom DOMEntity to XmlNode recursively
private XmlNode nodeFromDom(DOMEntity!string ent) {
    XmlNode n;
    if (ent.type == EntityType.elementStart || ent.type == EntityType.elementEmpty) {
        n.name = ent.name.idup;
        foreach (a; ent.attributes) {
            n.attributes[a.name.idup] = a.value.idup;
        }
        // Collect text nodes and element children
        foreach (c; ent.children) {
            switch (c.type) {
                case EntityType.text:
                    // Accumulate text content
                    if (n.text.length) n.text ~= c.text.idup; else n.text = c.text.idup;
                    break;
                case EntityType.elementStart, EntityType.elementEmpty:
                    n.children ~= nodeFromDom(c);
                    break;
                case EntityType.comment:
                    // Skip comments in tree; they can be handled separately if needed
                    break;
                default:
                    // ignore other entity types for simplicity (CDATA handled as text by parser)
                    break;
            }
        }
    }
    return n;
}

// Parse XML from string into XmlNode tree (root element)
XmlNode parseXml(string xml) {
    auto dom = parseDOM(xml);
    // Find first elementStart child as root
    foreach (child; dom.children) {
        if (child.type == EntityType.elementStart || child.type == EntityType.elementEmpty) {
            return nodeFromDom(child);
        }
    }
    return XmlNode.init;
}

// Parse XML from file path
XmlNode parseXmlFile(string path) {
    import std.file : readText;
    return parseXml(readText(path));
}

// Query helpers
XmlNode[] find(ref XmlNode node, string tag) {
    XmlNode[] matches;
    foreach (ref c; node.children) {
        if (c.name == tag) matches ~= c;
    }
    return matches;
}

XmlNode[] findAll(ref XmlNode node, string tag) {
    XmlNode[] matches;
    foreach (ref c; node.children) {
        if (c.name == tag) matches ~= c;
        auto rec = findAll(c, tag);
        matches ~= rec;
    }
    return matches;
}

string getAttr(ref XmlNode node, string name, string defaultValue = "") {
    auto p = name in node.attributes;
    return p ? *p : defaultValue;
}

void setAttr(ref XmlNode node, string name, string value) {
    node.attributes[name] = value;
}

string getText(ref XmlNode node) { return node.text; }
void setText(ref XmlNode node, string value) { node.text = value; }

// Convenience builders/generators
XmlNode makeNode(string tag, string[string] attrs = null, string text = "") {
    XmlNode n; n.name = tag; n.text = text; if (attrs.length) n.attributes = attrs.dup; return n;
}

void addChild(ref XmlNode parent, XmlNode child) { parent.children ~= child; }

// Build <parent><itemTag>v</itemTag>...</parent> from list of values
XmlNode fromList(string parentTag, string[] items, string itemTag = "item") {
    XmlNode p = makeNode(parentTag);
    foreach (it; items) {
        XmlNode c = makeNode(itemTag, null, it);
        p.children ~= c;
    }
    return p;
}

// Build XmlNode tree from simple Duende data:
// - dict: string[string] with keys: "tag" (string), optional "attrs" (string[string]),
//         optional "text" (string), optional "children" (XmlNode[] built from lists)
// - list: string[] treated as repeated <item> children with text
// For simplicity when called from Duende (stringly-typed), we support two shapes:
// 1) Root as dict {"tag": name, "attrs": {...}, "children": [ ... dict or string ... ]}
// 2) Root as dict {"tag": name, "text": "..."}
XmlNode fromData(string[string] data, XmlNode[] children = null) {
    XmlNode n;
    if (auto ptag = "tag" in data) n.name = *ptag; else n.name = "root";
    // Attributes: expect keys with prefix "@" or nested map encoded as JSON-like string "key=value;..."
    // Since Duende dicts are string[string], we look for keys starting with '@'
    foreach (k, v; data) {
        if (k.length && k[0] == '@') {
            n.attributes[k[1 .. $]] = v;
        }
    }
    if (auto ptext = "text" in data) n.text = *ptext;
    if (children.length) n.children = children.dup;
    return n;
}

// Render XmlNode to XML string (compact, no pretty newlines/indents)
string toXml(ref XmlNode node) {
    import std.array : appender;
    auto buf = appender!string();
    auto w = xmlWriter(buf);
    alias Writer = typeof(w);

    void writeAttrsSorted(ref Writer wr, ref string[string] attrs) {
        string[] ks;
        foreach (k, _; attrs) ks ~= k;
        ks.sort();
        foreach (k; ks) wr.writeAttr(k, attrs[k]);
    }

    void writeNodeCompact(ref Writer wr, ref XmlNode n) {
        wr.openStartTag(n.name, Newline.no);
        writeAttrsSorted(wr, n.attributes);
        const bool leaf = (n.children.length == 0 && n.text.length == 0);
        if (leaf) {
            wr.closeStartTag(EmptyTag.yes);
            return;
        }
        wr.closeStartTag();
        if (n.text.length) wr.writeText(n.text, InsertIndent.no, Newline.no);
        foreach (ref c; n.children) writeNodeCompact(wr, c);
        wr.writeEndTag(n.name, Newline.no);
    }

    writeNodeCompact(w, node);
    return buf.data;
}

// Pretty-printed XML with indentation and newlines
string toXmlPretty(ref XmlNode node) {
    import std.array : appender;
    auto buf = appender!string();
    auto w = xmlWriter(buf);
    alias Writer = typeof(w);

    void writeAttrsSorted(ref Writer wr, ref string[string] attrs) {
        string[] ks; foreach (k, _; attrs) ks ~= k; ks.sort();
        foreach (k; ks) wr.writeAttr(k, attrs[k]);
    }

    void writeNodePretty(ref Writer wr, ref XmlNode n, bool isRoot) {
        wr.openStartTag(n.name, isRoot ? Newline.no : Newline.yes);
        writeAttrsSorted(wr, n.attributes);
        const bool leaf = (n.children.length == 0 && n.text.length == 0);
        if (leaf) { wr.closeStartTag(EmptyTag.yes); return; }
        wr.closeStartTag();
        if (n.text.length) wr.writeText(n.text);
        foreach (ref c; n.children) writeNodePretty(wr, c, false);
        wr.writeEndTag(n.name);
    }

    writeNodePretty(w, node, true);
    return buf.data;
}
