# Canonical units and the conversions between the ones that turn up in steel research.

# unit token (lower case, punctuation stripped) => (canonical symbol, quantity kind,
# factor to the SI reference unit)
const UNIT_TABLE = Dict{String,Tuple{String,String,Float64}}(
    # length
    "in" => ("in", "length", 0.0254), "inch" => ("in", "length", 0.0254), "inches" => ("in", "length", 0.0254),
    "ft" => ("ft", "length", 0.3048), "feet" => ("ft", "length", 0.3048),
    "mm" => ("mm", "length", 0.001), "cm" => ("cm", "length", 0.01), "m" => ("m", "length", 1.0),
    # force
    "kip" => ("kip", "force", 4448.222), "kips" => ("kip", "force", 4448.222),
    "lb" => ("lb", "force", 4.448222), "lbs" => ("lb", "force", 4.448222), "lbf" => ("lb", "force", 4.448222),
    "kn" => ("kN", "force", 1000.0), "n" => ("N", "force", 1.0),
    # stress
    "ksi" => ("ksi", "stress", 6.894757e6), "psi" => ("psi", "stress", 6894.757),
    "mpa" => ("MPa", "stress", 1.0e6), "gpa" => ("GPa", "stress", 1.0e9), "pa" => ("Pa", "stress", 1.0),
    # moment
    "kipin" => ("kip-in", "moment", 112.9848), "kipft" => ("kip-ft", "moment", 1355.818),
    "knm" => ("kN-m", "moment", 1000.0), "nm" => ("N-m", "moment", 1.0),
    # area
    "in2" => ("in²", "area", 6.4516e-4), "sqin" => ("in²", "area", 6.4516e-4),
    "ft2" => ("ft²", "area", 0.09290304), "sqft" => ("ft²", "area", 0.09290304),
    "mm2" => ("mm²", "area", 1.0e-6), "m2" => ("m²", "area", 1.0),
    # angle
    "rad" => ("rad", "angle", 1.0), "radians" => ("rad", "angle", 1.0),
    "deg" => ("deg", "angle", pi / 180), "degrees" => ("deg", "angle", pi / 180),
    # flow
    "cfm" => ("CFM", "flow", 4.719474e-4), "ls" => ("L/s", "flow", 1.0e-3),
    # dimensionless and labels
    "" => ("—", "dimensionless", 1.0), "-" => ("—", "dimensionless", 1.0),
    "ratio" => ("—", "dimensionless", 1.0), "dimensionless" => ("—", "dimensionless", 1.0),
    "pct" => ("%", "percentage", 1.0), "percent" => ("%", "percentage", 1.0), "%" => ("%", "percentage", 1.0),
    "text" => ("text", "category", 1.0), "category" => ("text", "category", 1.0), "count" => ("count", "count", 1.0),
)

normalize_unit_token(u) = lowercase(replace(String(u), r"[\s\.\_\^]+" => ""))

"""
    lookup_unit(u) -> Union{Nothing,NamedTuple}

`(symbol, kind, si_factor)` for a unit string, or `nothing` when it is not in the table.
"""
function lookup_unit(u::AbstractString)
    k = normalize_unit_token(u)
    haskey(UNIT_TABLE, k) || return nothing
    s, kind, f = UNIT_TABLE[k]
    return (symbol=s, kind=kind, si_factor=f)
end

"""
    conversion_factor(from, to) -> Union{Nothing,Float64}

Multiplier that takes a value in `from` to a value in `to`, or `nothing` when the two are
not the same kind of quantity (or either is unknown).
"""
function conversion_factor(from::AbstractString, to::AbstractString)
    a, b = lookup_unit(from), lookup_unit(to)
    (a === nothing || b === nothing) && return nothing
    a.kind == b.kind || return nothing
    b.si_factor == 0 && return nothing
    return a.si_factor / b.si_factor
end

# Preferred SI counterpart for each imperial canonical unit, used for the "= x" note.
const SI_PARTNER = Dict("in" => "mm", "ft" => "m", "kip" => "kN", "lb" => "N", "ksi" => "MPa",
                        "psi" => "MPa", "kip-in" => "kN-m", "kip-ft" => "kN-m", "in²" => "mm²",
                        "ft²" => "m²", "CFM" => "L/s", "deg" => "rad")

"""
    si_equivalent(unit) -> String

`"in"` → `"= 25.4 mm"`. Empty when the unit is already SI, dimensionless or unknown.
"""
function si_equivalent(unit::AbstractString)
    u = lookup_unit(unit)
    u === nothing && return ""
    partner = get(SI_PARTNER, u.symbol, "")
    isempty(partner) && return ""
    f = conversion_factor(u.symbol, partner)
    f === nothing && return ""
    return string("= ", fmt_factor(f), " ", partner)
end

function fmt_factor(f::Real)
    f == 1 && return "1"
    a = abs(f)
    d = a >= 100 ? 1 : a >= 1 ? 3 : 5
    s = string(round(f; digits=d))
    s = replace(s, r"0+$" => "")
    endswith(s, ".") && (s = chop(s))
    return s
end

"""
    conversion_note(from, to) -> String

`"kips" → "kip"` gives `""` (same unit); `"mm" → "in"` gives `"× 0.03937"`; an
incompatible or unknown pair gives `"check"`.
"""
function conversion_note(from::AbstractString, to::AbstractString)
    (isempty(strip(from)) || isempty(strip(to))) && return ""
    a, b = lookup_unit(from), lookup_unit(to)
    (a === nothing || b === nothing) && return normalize_unit_token(from) == normalize_unit_token(to) ? "" : "check"
    a.symbol == b.symbol && return ""
    f = conversion_factor(from, to)
    f === nothing && return "check"
    return string("× ", fmt_factor(f))
end
