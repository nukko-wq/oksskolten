package main

import rego.v1

# Helper: extract text from heading node children
heading_text(h) := concat("", [c.value | some c in h.children; c.type == "text"])

# All headings in the document
headings := [h | some h in input.children; h.type == "heading"]

# Rule 1: H1 must match title pattern
deny contains msg if {
	some h in headings
	h.depth == 1
	text := heading_text(h)
	not regex.match(`^Oksskolten Spec — .+$`, text)
	msg := sprintf("H1 must match 'Oksskolten Spec — {Feature}', got: '%s'", [text])
}

deny contains msg if {
	h1s := [h | some h in headings; h.depth == 1]
	count(h1s) != 1
	msg := sprintf("Spec must have exactly one H1, found %d", [count(h1s)])
}

# Rule 2: Feature specs must not have a redundant H2 repeating the feature name.
# Feature specs use H2 for sections (Overview, Motivation, etc.) — no standalone feature-name H2.
# (Enforced via Rule 8 allowed-H2 list; this rule number is reserved for clarity.)

# Rule 3: Forbidden section names
forbidden_prefixes := ["Current Status", "Implementation Checklist", "Discrepancies", "Updates", "Reference:"]

deny contains msg if {
	some h in headings
	text := heading_text(h)
	some prefix in forbidden_prefixes
	startswith(text, prefix)
	msg := sprintf("Forbidden section name: '%s'", [text])
}

# Rule 4: Key Files table must have 2 columns (File | Description)
deny contains msg if {
	some i, node in input.children
	node.type == "heading"
	node.depth == 3
	heading_text(node) == "Key Files"

	# Find the next table after this heading
	some j, tbl in input.children
	j > i
	tbl.type == "table"

	# Check column count via first row (header)
	header := tbl.children[0]
	col_count := count(header.children)
	col_count != 2
	msg := sprintf("Key Files table must have 2 columns (File | Description), found %d", [col_count])
}

# Rule 5: No heading deeper than H4
deny contains msg if {
	some h in headings
	h.depth > 4
	text := heading_text(h)
	msg := sprintf("Heading depth %d exceeds maximum (H4): '%s'", [h.depth, text])
}

# Rule 6: Non-overview specs must have "Back to Overview" blockquote immediately after H1
# Expected AST: children[0] = heading(depth=1), children[1] = blockquote containing
# a link to ./01_overview.md with text "Back to Overview" (title case).
# Skipped for 01_overview.md (it IS the overview).

deny contains msg if {
	filename := object.get(input, ["metadata", "filename"], "")
	filename != ""
	filename != "01_overview.md"
	count(input.children) >= 2
	input.children[0].type == "heading"
	input.children[0].depth == 1
	node := input.children[1]
	not _is_back_to_overview(node)
	msg := "Non-overview spec must have '> [Back to Overview](./01_overview.md)' immediately after H1"
}

deny contains msg if {
	filename := object.get(input, ["metadata", "filename"], "")
	filename != ""
	filename != "01_overview.md"
	count(input.children) < 2
	msg := "Non-overview spec must have '> [Back to Overview](./01_overview.md)' immediately after H1"
}

_is_back_to_overview(node) if {
	node.type == "blockquote"
	some para in node.children
	para.type == "paragraph"
	some link in para.children
	link.type == "link"
	link.url == "./01_overview.md"
	some text in link.children
	text.type == "text"
	text.value == "Back to Overview"
}

# Rule 7: 01_overview.md must link to every other spec file
# Uses walk() to collect all link URLs in the AST and checks that every file
# in all_filenames (except 01_overview.md) appears as "./filename".

_all_link_urls := {url | walk(input, [_, node]); node.type == "link"; url := node.url}

deny contains msg if {
	filename := object.get(input, ["metadata", "filename"], "")
	filename == "01_overview.md"
	all_filenames := object.get(input, ["metadata", "all_filenames"], [])
	some f in all_filenames
	f != "01_overview.md"
	expected_url := sprintf("./%s", [f])
	not expected_url in _all_link_urls
	msg := sprintf("01_overview.md must link to all spec files, missing: '%s'", [f])
}

# Rule 8: Templated spec H2 structure (feature + perf specs)
# Feature (8x) and perf (9x) specs share the same H2 template.
# Required H2s: Overview, Motivation, Design (in that order)
# Optional H2: Scope (must appear between Motivation and Design)
# No other H2s are allowed. H3s under Design are unrestricted.

_is_templated_spec if {
	object.get(input, ["metadata", "is_feature"], false) == true
}

_is_templated_spec if {
	object.get(input, ["metadata", "is_perf"], false) == true
}

_spec_type := "Feature" if {
	object.get(input, ["metadata", "is_feature"], false) == true
}

_spec_type := "Perf" if {
	not object.get(input, ["metadata", "is_feature"], false) == true
	object.get(input, ["metadata", "is_perf"], false) == true
}

_allowed_h2s := {"Overview", "Scope", "Motivation", "Design"}
_required_h2s := ["Overview", "Motivation", "Design"]

# Extract H2 names in order
_h2_names := [heading_text(h) | some h in input.children; h.type == "heading"; h.depth == 2]

# 8a: Required H2s must be present
deny contains msg if {
	_is_templated_spec
	some required in _required_h2s
	not required in {name | some name in _h2_names}
	msg := sprintf("%s spec must have '## %s' section", [_spec_type, required])
}

# 8b: Only allowed H2 names
deny contains msg if {
	_is_templated_spec
	some name in _h2_names
	not name in _allowed_h2s
	msg := sprintf("%s spec H2 must be one of {Overview, Scope, Motivation, Design}, got: '## %s'", [_spec_type, name])
}

# 8c: H2 order must be Overview → Motivation → (Scope) → Design
# Validate by checking that the sequence without Scope equals the required order.
_h2_names_without_scope := [name | some name in _h2_names; name != "Scope"]

deny contains msg if {
	_is_templated_spec
	# All required H2s are present (skip order check if missing — 8a handles that)
	every required in _required_h2s {
		required in {name | some name in _h2_names}
	}
	_h2_names_without_scope != _required_h2s
	msg := sprintf("%s spec H2 order must be: Overview → Motivation → (Scope) → Design", [_spec_type])
}

# 8d: Scope must appear between Motivation and Design (index check)
deny contains msg if {
	_is_templated_spec
	some i, name in _h2_names
	name == "Scope"
	some mi, mname in _h2_names
	mname == "Motivation"
	some di, dname in _h2_names
	dname == "Design"
	not _between(i, mi, di)
	msg := sprintf("%s spec '## Scope' must appear between Motivation and Design", [_spec_type])
}

_between(i, lo, hi) if {
	i > lo
	i < hi
}
