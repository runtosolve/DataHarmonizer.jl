# The concordance as a self-contained HTML page: description and meaning, canonical unit,
# availability, marks, paper code tags and the table tag behind every mark.

const PAGE_CSS = """
  :root{
    --paper:#f1f0ec; --card:#fbfaf7; --ink:#15202f; --slate:#5c6b7d; --faint:#8b97a5;
    --rule:#d3d6da; --hair:#e2e4e6; --direct:#2f7d5a; --direct-soft:#cfe3d8;
    --qual:#c25a16; --qual-soft:#f0dcc9; --absent:#a6adb6; --navy:#1b2a44; --track:#e4e5e3;
  }
  @media (prefers-color-scheme: dark){
    :root:not([data-theme="light"]){
      --paper:#101820; --card:#17212b; --ink:#e4e2db; --slate:#9aa7b4; --faint:#6d7b89;
      --rule:#2c3a49; --hair:#232f3c; --direct:#5fbe8c; --direct-soft:#1e4436;
      --qual:#f08640; --qual-soft:#4a2e18; --absent:#5b6875; --navy:#c3cedd; --track:#22303d;
    }
  }
  :root[data-theme="dark"]{
    --paper:#101820; --card:#17212b; --ink:#e4e2db; --slate:#9aa7b4; --faint:#6d7b89;
    --rule:#2c3a49; --hair:#232f3c; --direct:#5fbe8c; --direct-soft:#1e4436;
    --qual:#f08640; --qual-soft:#4a2e18; --absent:#5b6875; --navy:#c3cedd; --track:#22303d;
  }
  *{box-sizing:border-box}
  body{background:var(--paper);color:var(--ink);
    font-family:"IBM Plex Sans","Segoe UI",Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55;
    -webkit-font-smoothing:antialiased;margin:0}
  .wrap{max-width:1340px;margin:0 auto;padding:0 20px;padding-block:44px 64px;display:flex;flex-direction:column;gap:38px}
  .eyebrow{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11px;letter-spacing:.14em;
    text-transform:uppercase;color:var(--slate);margin:0 0 14px}
  h1{font-family:"IBM Plex Sans Condensed","IBM Plex Sans",sans-serif;font-weight:700;
    font-size:clamp(28px,4.2vw,44px);line-height:1.05;letter-spacing:-.015em;margin:0;text-wrap:balance}
  .lede{margin:14px 0 0;max-width:66ch;color:var(--slate);font-size:16px}
  .rule-heavy{height:2px;background:var(--ink);margin-top:22px;opacity:.85}
  .sec-head{display:flex;align-items:baseline;gap:14px;flex-wrap:wrap;margin-bottom:6px}
  h2{font-family:"IBM Plex Sans Condensed","IBM Plex Sans",sans-serif;font-weight:600;font-size:22px;margin:0}
  .sec-meta{font-family:"IBM Plex Mono",monospace;font-size:11.5px;color:var(--faint);letter-spacing:.04em}
  .sec-note{margin:0 0 18px;color:var(--slate);font-size:14px;max-width:74ch}
  .register{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:14px}
  .src{background:var(--card);border:1px solid var(--hair);border-top:3px solid var(--navy);padding:14px 16px 15px}
  .src-tag{font-family:"IBM Plex Mono",monospace;font-weight:600;font-size:13px;color:var(--ink)}
  .src-cite{font-size:13.5px;color:var(--slate);margin-top:3px;font-style:italic}
  .src-title{font-size:13.5px;margin-top:7px;line-height:1.45}
  .src-exp{font-size:12.5px;margin-top:8px;line-height:1.5;color:var(--slate)}
  .tagrow{display:flex;flex-wrap:wrap;gap:5px;margin-top:11px}
  .ttag{font-family:"IBM Plex Mono",monospace;font-size:10px;letter-spacing:.02em;padding:2px 6px;
    border:1px solid var(--rule);color:var(--slate);background:var(--paper);white-space:nowrap;cursor:help}
  .legend{display:flex;flex-wrap:wrap;gap:8px 26px;padding:14px 16px;background:var(--card);border:1px solid var(--hair)}
  .leg{display:flex;align-items:center;gap:8px;font-size:13px;color:var(--slate)}
  .leg b{color:var(--ink);font-weight:500}
  .mk{display:inline-flex;align-items:center;justify-content:center;width:17px;height:17px;flex:0 0 17px;
    border-radius:2px;font-size:11px;font-weight:700;line-height:1}
  .mk.direct{background:var(--direct-soft);color:var(--direct)}
  .mk.qual{background:var(--qual-soft);color:var(--qual)}
  .mk.absent{background:transparent;color:var(--absent);border:1px solid var(--rule)}
  .qcode{font-family:"IBM Plex Mono",monospace;font-size:9.5px;font-weight:600;letter-spacing:.06em;
    color:var(--qual);text-transform:uppercase}
  .scroll{overflow-x:auto;border:1px solid var(--rule);background:var(--card)}
  table{border-collapse:collapse;width:100%;font-size:13.5px}
  thead th{position:sticky;top:0;z-index:3;background:var(--card);
    font-family:"IBM Plex Sans Condensed","IBM Plex Sans",sans-serif;font-weight:600;font-size:12px;
    letter-spacing:.06em;text-transform:uppercase;color:var(--slate);text-align:left;vertical-align:bottom;
    padding:12px 12px 9px;border-bottom:2px solid var(--ink);white-space:nowrap}
  thead th .code{display:block;font-family:"IBM Plex Mono",monospace;font-size:12.5px;letter-spacing:.01em;
    text-transform:none;color:var(--ink);font-weight:600}
  thead th .yr{display:block;font-size:11px;text-transform:none;letter-spacing:0;color:var(--faint);
    font-weight:400;font-style:italic}
  tbody td{padding:11px 12px;border-bottom:1px solid var(--hair);vertical-align:top}
  tbody tr:hover td{background:color-mix(in srgb,var(--navy) 4%,transparent)}
  tr.role-break td{background:var(--paper);border-bottom:1px solid var(--rule);padding:9px 12px 7px}
  tr.role-break span{font-family:"IBM Plex Sans Condensed","IBM Plex Sans",sans-serif;font-size:11.5px;
    font-weight:600;letter-spacing:.1em;text-transform:uppercase;color:var(--slate)}
  .c-var{min-width:250px}
  th.c-var,td.c-var{position:sticky;left:0;z-index:2;background:var(--card)}
  thead th.c-var{z-index:4}
  tr.role-break td.c-var{background:var(--paper)}
  tbody tr:hover td.c-var{background:color-mix(in srgb,var(--navy) 4%,var(--card))}
  .vname{font-weight:600;font-size:14px;line-height:1.3}
  .vdesc{color:var(--slate);font-size:12.5px;line-height:1.45;margin-top:3px;max-width:38ch}
  .c-unit{min-width:96px;white-space:nowrap}
  .unit{font-family:"IBM Plex Mono",monospace;font-weight:500;font-size:13px}
  .unit-si{display:block;font-family:"IBM Plex Mono",monospace;font-size:10.5px;color:var(--faint);margin-top:3px}
  .c-avail{min-width:128px}
  .bar{display:flex;height:6px;background:var(--track);overflow:hidden;margin-bottom:5px}
  .bar span{display:block;height:100%}
  .bar .s-direct{background:var(--direct)}
  .bar .s-qual{background:var(--qual)}
  .avail-n{font-family:"IBM Plex Mono",monospace;font-size:12.5px;font-weight:600;font-variant-numeric:tabular-nums}
  .avail-sub{font-size:11px;color:var(--faint);margin-top:1px}
  .cell{display:flex;gap:7px;align-items:flex-start}
  .cell-body{min-width:0}
  .sym{font-family:"IBM Plex Mono",monospace;font-size:12px;font-weight:500;line-height:1.35;word-break:break-word}
  .sym.none{color:var(--absent);font-style:italic;font-family:inherit;font-size:12.5px}
  .from{display:inline-block;margin-top:4px;margin-right:3px;font-family:"IBM Plex Mono",monospace;font-size:10px;
    color:var(--slate);border:1px solid var(--rule);padding:1px 5px;cursor:help;white-space:nowrap}
  .conv{display:inline-block;margin-top:4px;font-family:"IBM Plex Mono",monospace;font-size:10px;
    color:var(--qual);border:1px solid var(--qual);padding:1px 5px;white-space:nowrap}
  .qnote{font-size:11.5px;color:var(--slate);margin-top:3px;line-height:1.4;font-style:italic}
  .c-paper{min-width:176px}
  .notes{border-top:2px solid var(--ink);padding-top:18px;display:grid;
    grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:22px}
  .note h3{font-family:"IBM Plex Sans Condensed","IBM Plex Sans",sans-serif;font-size:13px;letter-spacing:.07em;
    text-transform:uppercase;color:var(--slate);margin:0 0 7px;font-weight:600}
  .note p,.note li{margin:0 0 9px;font-size:13.5px;color:var(--slate);line-height:1.55}
  .note ul{margin:0;padding-left:18px}
  .note code{font-family:"IBM Plex Mono",monospace;font-size:12px;color:var(--ink);background:var(--card);
    padding:1px 4px;border:1px solid var(--hair)}
  .colophon{font-family:"IBM Plex Mono",monospace;font-size:11px;color:var(--faint);letter-spacing:.03em}
  @media (max-width:640px){
    .wrap{padding-block:32px 48px;gap:30px}
    th.c-var,td.c-var{position:static}
    .c-var{min-width:210px}
  }
"""

esc(s) = xml_escape(String(s))

short_tag(tag, paper) = begin
    t = String(tag)
    s = startswith(t, paper * "_") ? t[length(paper)+2:end] : t
    m = match(r"^TABLE([A-Za-z0-9\.\-_]+?)_"i, s)
    m === nothing ? first(s, 18) : "T" * String(m[1])
end

function mark_html(c::Concordance, m::Union{Nothing,Member}, paper::AbstractString)
    m === nothing && return "<div class=\"cell\"><span class=\"mk absent\">&times;</span><div class=\"cell-body\"><div class=\"sym none\">not addressed</div></div></div>"
    io = IOBuffer()
    cls = is_direct(m) ? "direct" : "qual"
    print(io, "<div class=\"cell\"><span class=\"mk ", cls, "\">&check;</span><div class=\"cell-body\">")
    is_direct(m) || print(io, "<span class=\"qcode\">", esc(m.availability), "</span>")
    syms = split_symbols(m.symbol)
    isempty(syms) || print(io, "<div class=\"sym\">", join((esc(s) for s in syms), "<br>"), "</div>")
    if !is_direct(m) && !isempty(m.evidence)
        print(io, "<div class=\"qnote\">", esc(m.evidence), "</div>")
    end
    for t in m.table_tags
        lbl = get(c.tag_labels, t, "")
        print(io, "<span class=\"from\" title=\"", esc(t), isempty(lbl) ? "" : " &mdash; " * esc(lbl),
              "\">", esc(chip_label(c, t, paper)), "</span>")
    end
    if isempty(m.table_tags) && is_direct(m) && !isempty(m.evidence)
        print(io, "<span class=\"from\" title=\"", esc(m.evidence), "\">", esc(first(m.evidence, 16)), "</span>")
    end
    isempty(m.conversion) || print(io, "<span class=\"conv\" title=\"reported in ", esc(m.unit),
                                   ", converted to the canonical unit\">", esc(m.conversion), "</span>")
    print(io, "</div></div>")
    return String(take!(io))
end

function avail_html(v::CanonicalVariable)
    dpct = v.n_papers == 0 ? 0 : 100 * v.n_direct / v.n_papers
    qpct = v.n_papers == 0 ? 0 : 100 * v.n_qualified / v.n_papers
    io = IOBuffer()
    print(io, "<div class=\"bar\">")
    dpct > 0 && print(io, "<span class=\"s-direct\" style=\"width:", round(dpct; digits=2), "%\"></span>")
    qpct > 0 && print(io, "<span class=\"s-qual\" style=\"width:", round(qpct; digits=2), "%\"></span>")
    print(io, "</div><div class=\"avail-n\">", v.n_present, " / ", v.n_papers, " &middot; ",
          round(Int, availability_pct(v)), "%</div><div class=\"avail-sub\">")
    parts = String[]
    v.n_direct > 0 && push!(parts, string(v.n_direct, " direct"))
    v.n_qualified > 0 && push!(parts, string(v.n_qualified, " qualified"))
    v.n_papers - v.n_present > 0 && push!(parts, string(v.n_papers - v.n_present, " absent"))
    print(io, join(parts, " &middot; "), "</div>")
    return String(take!(io))
end

"""
    render_concordance(c::Concordance) -> String

The concordance as one self-contained HTML document.
"""
function render_concordance(c::Concordance)
    codes = [p.code_tag for p in c.papers]
    io = IOBuffer()
    print(io, "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n")
    print(io, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">\n")
    print(io, "<title>", esc(c.set_title), "</title>\n")
    print(io, "<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">\n")
    print(io, "<link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>\n")
    print(io, "<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans+Condensed:wght@500;600;700&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;1,400&display=swap\">\n")
    print(io, "<style>", PAGE_CSS, "</style>\n</head>\n<body>\n<div class=\"wrap\">\n")

    # masthead
    print(io, "<header>\n<p class=\"eyebrow\">SteelData Initiative &middot; Module 4 &middot; Harmonization</p>\n")
    print(io, "<h1>Summary Table of Common Measured Variables</h1>\n<div class=\"rule-heavy\"></div>\n")
    print(io, "<p class=\"lede\"><strong>", esc(c.set_title), ".</strong> ", esc(c.summary), "</p>\n</header>\n")

    # source register
    ntab = sum(length(p.tables) for p in c.papers)
    print(io, "<section>\n<div class=\"sec-head\"><h2>Source register</h2><span class=\"sec-meta\">",
          length(c.papers), " PAPERS &middot; ", ntab, " TABLES</span></div>\n")
    print(io, "<p class=\"sec-note\">Chips are the tag of every extracted table read for that paper. ",
          "Every mark in the concordance carries the tag it came from, so a row resolves back to a file on disk.</p>\n")
    print(io, "<div class=\"register\">\n")
    for p in c.papers
        print(io, "<article class=\"src\">\n<div class=\"src-tag\">", esc(p.code_tag), "</div>\n")
        cit = citation_of(c, p.code_tag)
        isempty(cit) || print(io, "<div class=\"src-cite\">", esc(cit), "</div>\n")
        ttl = title_of(c.inventories, p.code_tag)
        isempty(ttl) && (ttl = p.title)
        isempty(ttl) || print(io, "<div class=\"src-title\">", esc(ttl), "</div>\n")
        exp = experiment_of(c.inventories, p.code_tag)
        isempty(exp) || print(io, "<div class=\"src-exp\">", esc(exp), "</div>\n")
        print(io, "<div class=\"tagrow\">")
        for t in p.tables
            print(io, "<span class=\"ttag\" title=\"", esc(t.tag), isempty(t.pages) ? "" : " &mdash; pp." * esc(t.pages),
                  isempty(t.content) ? "" : " &mdash; " * esc(t.content),
                  "\">", esc(chip_label(c, t.tag, p.code_tag)), " ", esc(first(t.content, 24)), "…</span>")
        end
        print(io, "</div>\n</article>\n")
    end
    print(io, "</div>\n</section>\n")

    # legend
    print(io, "<section>\n<div class=\"legend\">")
    print(io, "<span class=\"leg\"><span class=\"mk direct\">&check;</span><b>Direct</b> &mdash; reported as its own column</span>")
    print(io, "<span class=\"leg\"><span class=\"mk qual\">&check;</span><b>Implied</b> &mdash; stated in a note, not a column</span>")
    print(io, "<span class=\"leg\"><span class=\"mk qual\">&check;</span><b>Inferred</b> &mdash; needs outside context or a figure</span>")
    print(io, "<span class=\"leg\"><span class=\"mk qual\">&check;</span><b>Simulated</b> &mdash; from a model or code equation</span>")
    print(io, "<span class=\"leg\"><span class=\"mk absent\">&times;</span><b>Absent</b> &mdash; not addressed</span>")
    print(io, "</div>\n</section>\n")

    # main table
    shared = count(v -> v.n_present == v.n_papers, c.variables)
    print(io, "<section>\n<div class=\"sec-head\"><h2>Concordance</h2><span class=\"sec-meta\">",
          length(c.variables), " CANONICAL VARIABLES &middot; ", shared, " IN EVERY PAPER</span></div>\n")
    print(io, "<p class=\"sec-note\">Rows are grouped by what the quantity does in the experiment, ",
          "measured outputs first. Hover a tag chip for the full table tag it resolves to.</p>\n")
    print(io, "<div class=\"scroll\">\n<table>\n<thead>\n<tr>")
    print(io, "<th class=\"c-var\">Common variable</th><th class=\"c-unit\">Canonical unit</th><th class=\"c-avail\">Availability</th>")
    for p in c.papers
        cit = citation_of(c, p.code_tag)
        print(io, "<th class=\"c-paper\"><span class=\"code\">", esc(p.code_tag), "</span><span class=\"yr\">", esc(cit), "</span></th>")
    end
    print(io, "</tr>\n</thead>\n<tbody>\n")
    lastrole = ""
    ncols = 3 + length(codes)
    for v in c.variables
        if v.role != lastrole
            print(io, "<tr class=\"role-break\"><td class=\"c-var\" colspan=\"", ncols, "\"><span>", esc(role_label(v.role)), "</span></td></tr>\n")
            lastrole = v.role
        end
        print(io, "<tr>\n<td class=\"c-var\"><div class=\"vname\">", esc(v.name), "</div><div class=\"vdesc\">", esc(v.description), "</div></td>\n")
        print(io, "<td class=\"c-unit\"><span class=\"unit\">", esc(isempty(v.canonical_unit) ? "—" : v.canonical_unit), "</span>")
        isempty(v.si_equivalent) || print(io, "<span class=\"unit-si\">", esc(v.si_equivalent), "</span>")
        print(io, "</td>\n<td class=\"c-avail\">", avail_html(v), "</td>\n")
        for p in c.papers
            print(io, "<td class=\"c-paper\">", mark_html(c, get(v.members, p.code_tag, nothing), p.code_tag), "</td>\n")
        end
        print(io, "</tr>\n")
    end
    print(io, "</tbody>\n</table>\n</div>\n</section>\n")

    # notes
    print(io, "<section class=\"notes\">\n")
    print(io, "<div class=\"note\"><h3>How a row is built</h3><p>Every quantity in every extracted table is ",
          "inventoried under the exact column name the paper printed, one paper at a time. Those inventories are then ",
          "clustered by physical meaning, so the same quantity under three different symbols becomes one row. ",
          "Notation is normalised only at the end, never before the clustering.</p></div>\n")
    print(io, "<div class=\"note\"><h3>Units</h3><p>One canonical unit per row, the one most common across the sources, ",
          "with its SI equivalence beside it. A paper reporting in another unit keeps its own value in its CSV and ",
          "carries a conversion chip here, so the step is visible and reversible.</p></div>\n")
    print(io, "<div class=\"note\"><h3>Availability</h3><p>The fraction counts every paper where the variable can be ",
          "obtained at all. The bar splits that into directly reported and qualified, because a row that is fully ",
          "available but mostly implied is weaker than one that is fully direct, and a single percentage hides it.</p></div>\n")
    if !isempty(c.notes)
        print(io, "<div class=\"note\"><h3>Judgement calls to review</h3><ul>")
        for n in c.notes
            print(io, "<li>", esc(n), "</li>")
        end
        print(io, "</ul></div>\n")
    end
    if !isempty(c.checks)
        print(io, "<div class=\"note\"><h3>Automatic checks</h3><ul>")
        for n in first(c.checks, 12)
            print(io, "<li>", esc(n), "</li>")
        end
        length(c.checks) > 12 && print(io, "<li>", length(c.checks) - 12, " more in the run log</li>")
        print(io, "</ul></div>\n")
    end
    print(io, "<div class=\"note\"><h3>Traceability</h3><p>Each mark carries the tag of the table it came from, ",
          "matching the tag line in the extracted CSV. <code>source_tables.csv</code> resolves every tag to a file, ",
          "a table label and a page range in the original report.</p>",
          "<p class=\"colophon\">SteelData Initiative &middot; Module 4 &middot; ",
          esc(Dates.format(today(), "yyyy-mm-dd")), "</p></div>\n")
    print(io, "</section>\n</div>\n</body>\n</html>\n")
    return String(take!(io))
end
