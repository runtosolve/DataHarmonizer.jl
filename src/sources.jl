# Reading a folder of extracted data CSVs. Header conventions vary between extraction
# runs, so the parser is deliberately tolerant: it accepts `# Tag:` or `# TAG:`,
# `# Content:` or `# EXPERIMENT_TYPE:`, a `# COLUMNS:` block of per-column definitions or
# a `# Column definitions:` block, and falls back to the filename when a field is absent.

"""
    TableFile

One extracted data CSV: its header metadata, column names, per-column definitions where
the header carries them, and the data rows.
"""
struct TableFile
    paper::String                    # code tag, e.g. "MBMA_9408"
    path::String
    name::String
    tag::String                      # the table's own tag, used for traceability
    table_label::String              # "Table VII", "Table 3.3"
    pages::String
    source_title::String
    citation::String                 # "Cain, D.E. (1995)", parsed from the header
    content::String                  # what the table holds / the experiment behind it
    units::String
    notes::Vector{String}            # remaining header lines (flags, footnotes, caveats)
    coldefs::Dict{String,String}     # column name => definition, when the header gives them
    columns::Vector{String}
    rows::Vector{Vector{String}}
end

nrows(t::TableFile) = length(t.rows)
Base.show(io::IO, t::TableFile) = print(io, "TableFile(", t.paper, " ", t.tag, ", ",
    length(t.rows), "×", length(t.columns), ")")

"""
    Paper

One source paper and every data table found for it.
"""
struct Paper
    code_tag::String
    title::String
    citation::String            # parsed from the CSV headers, never inferred
    tables::Vector{TableFile}
end
Base.show(io::IO, p::Paper) = print(io, "Paper(", p.code_tag, ", ", length(p.tables), " tables)")

"""
    citation_from_header(source_line, source_title) -> String

Pull "Bhakta (1992)" out of `# Source: MBMA_9007 | Bhakta (1992), Table X, p.36`, or
"Holesapple & LaBoube, 2002" out of a `SOURCE_TITLE` ending in a parenthesised citation.
Returns "" when the headers do not state one.
"""
function citation_from_header(source_line::AbstractString, source_title::AbstractString)
    m = match(r"\|\s*(.+?\(\s*\d{4}[a-z]?\s*\))", source_line)
    m === nothing || return String(strip(m[1]))
    # "... (Holesapple & LaBoube, 2002, CES 02-1)" → "Holesapple & LaBoube (2002)"
    m = match(r"\(([^()]*?),\s*(\d{4})[a-z]?(?:,[^()]*)?\)\s*$", strip(source_title))
    m === nothing || return string(strip(m[1]), " (", m[2], ")")
    return ""
end

# Files that are not data tables.
is_lock(name) = startswith(basename(name), "~\$")
is_csv(name) = occursin(r"\.csv$"i, name)
const NON_DATA_EXT = r"\.(docx?|pdf|xlsx?|pptx?|txt|md|json)$"i

strip_hash(line) = String(strip(replace(line, r"^#\s?" => "")))

# Header keys whose content is a remark to keep rather than a field to store once. These
# carry the caveats that decide whether a variable is directly reported or only implied.
const NOTE_KEYS = Set(["NOTE", "NOTES", "FLAG", "FLAGS", "CAVEAT", "WARNING", "ANOMALYFLAG"])

# "# KEY: value" → ("KEY", "value"); returns nothing when the line carries no key.
function header_field(line::AbstractString)
    m = match(r"^#\s*([A-Za-z][A-Za-z0-9 _\-]{0,40}?)\s*:\s*(.*)$", line)
    m === nothing && return nothing
    return (uppercase(replace(String(m[1]), r"[\s_]+" => "")), String(strip(m[2])))
end

"""
    parse_table_csv(path) -> TableFile

Read one extracted CSV: header comment block, then the column header row, then data rows.
"""
function parse_table_csv(path::AbstractString)
    comments = String[]
    header = String[]
    rows = Vector{String}[]
    for line in eachline(path)
        s = rstrip(line, ['\r', '\n'])
        if startswith(s, "#") && isempty(header)
            push!(comments, s)
        elseif isempty(strip(s))
            continue
        elseif isempty(header)
            header = parse_csv_line(s)
        else
            push!(rows, parse_csv_line(s))
        end
    end

    fields = Dict{String,String}()
    notes = String[]
    coldefs = Dict{String,String}()
    in_coldefs = false
    consumed = Set{Int}()          # indices already taken as a wrapped continuation
    for (i, c) in enumerate(comments)
        i in consumed && continue
        body = strip_hash(c)
        # a "# COLUMNS:" / "# Column definitions:" line opens a block of "name - meaning"
        if occursin(r"^(COLUMNS|Column definitions)\s*:?\s*$"i, body)
            in_coldefs = true
            continue
        end
        if in_coldefs
            m = match(r"^([A-Za-z_][A-Za-z0-9_\-/\.]*)\s*(?:[-–—=]|:)\s*(.+)$", body)
            if m !== nothing
                coldefs[String(m[1])] = String(strip(m[2]))
                continue
            end
            # an indented continuation of the previous definition
            if startswith(c, "#   ") && !isempty(coldefs)
                continue
            end
            in_coldefs = false
        end
        f = header_field(c)
        if f === nothing
            isempty(body) || push!(notes, body)
            continue
        end
        key, val = f
        # a wrapped value continues on the following indented lines
        j = i + 1
        while j <= length(comments) && startswith(comments[j], "#   ") && header_field(comments[j]) === nothing
            val *= " " * strip_hash(comments[j])
            push!(consumed, j)
            j += 1
        end
        if key in NOTE_KEYS || haskey(fields, key)
            # notes, flags and caveats are kept in full, and so is a repeated field
            push!(notes, key in NOTE_KEYS ? val : body)
        else
            fields[key] = val
        end
    end

    g(keys...) = (for k in keys; haskey(fields, k) && return fields[k]; end; "")

    stem = splitext(basename(path))[1]
    paper = g("SOURCEID")
    if isempty(paper)
        m = match(r"^\s*([A-Za-z]{2,}[_\-]\d{2,}[A-Za-z]?)\s*\|", g("SOURCE"))
        paper = m === nothing ? "" : uppercase(String(m[1]))
    end
    if isempty(paper)
        m = match(r"^([A-Za-z]{2,}[_\-]\d{2,}[A-Za-z]?)", stem)
        paper = m === nothing ? stem : uppercase(String(m[1]))
    end

    tag = g("TAG")
    isempty(tag) && (tag = uppercase(replace(stem, r"[^A-Za-z0-9]+" => "_")))
    startswith(uppercase(tag), uppercase(paper)) || (tag = string(paper, "_", tag))

    table_line = g("TABLE", "SOURCE")
    tl = match(r"(Table\s+[A-Za-z0-9\.\-]+)", table_line)
    table_label = tl === nothing ? "" : String(tl[1])
    if isempty(table_label)
        m = match(r"[Tt]able[_\- ]?([A-Za-z0-9\.\-]+)", stem)
        table_label = m === nothing ? "" : "Table " * String(m[1])
    end
    pm = match(r"pp?\.\s*([0-9\-–,\s]+)", table_line)
    pages = pm === nothing ? "" : String(strip(pm[1]))

    # only a real title field counts; a "# Source:" line is a citation, not a title
    src_title = g("SOURCETITLE", "TITLE")
    if isempty(src_title)
        m = match(r"[\"“]([^\"”]{12,})[\"”]", g("SOURCE"))
        m === nothing || (src_title = String(m[1]))
    end
    return TableFile(paper, abspath(path), basename(path), tag, table_label, pages,
                     src_title, citation_from_header(g("SOURCE"), g("SOURCETITLE", "TITLE")),
                     g("CONTENT", "EXPERIMENTTYPE", "DESCRIPTION"),
                     g("UNITS"), notes, coldefs, header, rows)
end

"""
    collect_papers(input; recursive=true) -> Vector{Paper}

Find every data CSV under `input` (a folder, possibly with one sub-folder per paper) and
group them by paper code tag. Word documents, lock files and byte-identical duplicates
are skipped.
"""
function collect_papers(input::AbstractString; recursive::Bool=true)
    isdir(input) || throw(ArgumentError("no such folder: $input"))
    paths = String[]
    if recursive
        for (root, _, files) in walkdir(input)
            for f in files
                is_csv(f) && !is_lock(f) && push!(paths, joinpath(root, f))
            end
        end
    else
        for f in readdir(input; join=true)
            isfile(f) && is_csv(f) && !is_lock(f) && push!(paths, f)
        end
    end
    sort!(paths)
    skipped = [f for (r, _, fs) in walkdir(input) for f in fs if occursin(NON_DATA_EXT, f) && !is_lock(f)]
    isempty(skipped) || @info "Skipping $(length(skipped)) non-CSV file(s) (extraction guides, PDFs)" examples = first(skipped, 3)

    tables = TableFile[]
    seen = Set{String}()
    for p in paths
        t = try
            parse_table_csv(p)
        catch e
            @warn "could not read CSV; skipping" file = basename(p) error = sprint(showerror, e)
            continue
        end
        isempty(t.columns) && (@warn "no column header; skipping" file = t.name; continue)
        key = string(t.paper, "|", t.tag, "|", length(t.rows), "|", join(t.columns, ","))
        key in seen && (@info "duplicate table; skipping" file = t.name; continue)
        push!(seen, key)
        push!(tables, t)
    end
    isempty(tables) && throw(ArgumentError("no data CSVs found in $input"))

    papers = Paper[]
    first_nonempty(f, ts) = (for t in ts; v = f(t); isempty(v) || return v; end; "")
    for code in sort(unique(t.paper for t in tables))
        ts = filter(t -> t.paper == code, tables)
        push!(papers, Paper(code, first_nonempty(t -> t.source_title, ts),
                            first_nonempty(t -> t.citation, ts), ts))
    end
    return papers
end

# ---- the compact view of a paper that pass 1 reads -------------------------------------------

"""
    paper_digest(p::Paper; sample_rows=3) -> String

Everything the inventory pass needs from one paper: each table's tag, label, pages,
description, units line, notes, column names with any definitions, and a few data rows so
the model can see the shape and magnitude of the values. Data rows beyond the sample are
left out — harmonization is about the columns, not the measurements.
"""
function paper_digest(p::Paper; sample_rows::Int=3)
    io = IOBuffer()
    println(io, "PAPER CODE TAG: ", p.code_tag)
    isempty(p.title) || println(io, "SOURCE: ", p.title)
    println(io, "TABLES: ", length(p.tables))
    for t in p.tables
        println(io, "\n<table tag=\"", t.tag, "\">")
        isempty(t.table_label) || println(io, "label: ", t.table_label, isempty(t.pages) ? "" : "  pages: " * t.pages)
        isempty(t.content) || println(io, "content: ", t.content)
        isempty(t.units) || println(io, "units: ", t.units)
        for n in t.notes
            println(io, "note: ", n)
        end
        println(io, "columns:")
        for c in t.columns
            d = get(t.coldefs, c, "")
            println(io, "  - ", c, isempty(d) ? "" : "  — " * d)
        end
        if sample_rows > 0 && !isempty(t.rows)
            println(io, "first ", min(sample_rows, length(t.rows)), " of ", length(t.rows), " data rows:")
            for r in first(t.rows, sample_rows)
                println(io, "  ", join(r, " | "))
            end
        end
        println(io, "</table>")
    end
    return String(take!(io))
end
