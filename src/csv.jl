# Tiny CSV reader/writer (RFC-4180 quoting) and an XML escaper. Kept local so the
# package has no dependency on the other pipeline modules.

"""
    parse_csv_line(line) -> Vector{String}

Split one CSV line: fields separated by commas, double quotes for quoting, doubled
quotes inside quoted fields.
"""
function parse_csv_line(line::AbstractString)
    fields = String[]
    buf = IOBuffer()
    inq = false
    chars = collect(line)
    i = 1
    while i <= length(chars)
        c = chars[i]
        if inq
            if c == '"'
                if i < length(chars) && chars[i+1] == '"'
                    write(buf, '"'); i += 1
                else
                    inq = false
                end
            else
                write(buf, c)
            end
        else
            if c == '"'
                inq = true
            elseif c == ','
                push!(fields, String(take!(buf)))
            else
                write(buf, c)
            end
        end
        i += 1
    end
    push!(fields, String(take!(buf)))
    return fields
end

"""
    read_csv(path) -> (header::Vector{String}, rows::Vector{Vector{String}})

Read a CSV file, skipping `#` comment lines and blank lines.
"""
function read_csv(path::AbstractString)
    header = String[]
    rows = Vector{String}[]
    for line in eachline(path)
        s = rstrip(line, ['\r', '\n'])
        isempty(strip(s)) && continue
        startswith(strip(s), "#") && continue
        f = parse_csv_line(s)
        if isempty(header)
            header = f
        else
            push!(rows, f)
        end
    end
    return header, rows
end

function csv_field(s::AbstractString)
    needs = occursin(r"[,\"\r\n]", s) || startswith(s, " ") || endswith(s, " ")
    needs || return String(s)
    return "\"" * replace(s, "\"" => "\"\"") * "\""
end
csv_line(fields) = join((csv_field(String(f)) for f in fields), ",")

xml_escape(s::AbstractString) = replace(String(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")
