# Minimal Anthropic Messages API client: one POST with retries, JSON-schema output.
# Same shape as the client in the other pipeline modules, kept local on purpose.

const API_URL = "https://api.anthropic.com/v1/messages"
const API_VERSION = "2023-06-01"
const DEFAULT_MODEL = "claude-opus-5"
const FALLBACK_BETA = "server-side-fallback-2026-07-01"

struct AnthropicError <: Exception
    status::Int
    type::String
    message::String
end
Base.showerror(io::IO, e::AnthropicError) =
    print(io, "AnthropicError (HTTP ", e.status, ", ", e.type, "): ", e.message)

# ---- API key discovery -------------------------------------------------------------

function default_dotenv_dirs()
    dirs = String[]
    d = pwd()
    for _ in 1:4
        push!(dirs, d)
        p = dirname(d)
        p == d && break
        d = p
    end
    push!(dirs, normpath(joinpath(@__DIR__, "..", "..")))
    push!(dirs, normpath(joinpath(@__DIR__, "..")))
    return unique(dirs)
end

"""
    load_dotenv!(dirs=default_dotenv_dirs()) -> Union{Nothing,String}

If `ENV["ANTHROPIC_API_KEY"]` is unset, read it from the first `.env` file found in
`dirs` (working directory, its parents, the folder above this package).
"""
function load_dotenv!(dirs::AbstractVector{<:AbstractString}=default_dotenv_dirs())
    isempty(get(ENV, "ANTHROPIC_API_KEY", "")) || return nothing
    for d in dirs
        f = joinpath(d, ".env")
        isfile(f) || continue
        for line in eachline(f)
            m = match(r"^\s*(?:export\s+)?ANTHROPIC_API_KEY\s*=\s*(.+?)\s*$", line)
            m === nothing && continue
            v = strip(m[1], ['"', '\''])
            if !isempty(v)
                ENV["ANTHROPIC_API_KEY"] = String(v)
                return f
            end
        end
    end
    return nothing
end

function resolve_api_key(explicit)
    explicit === nothing || return String(explicit)
    load_dotenv!()
    k = get(ENV, "ANTHROPIC_API_KEY", "")
    isempty(k) && throw(ArgumentError(
        "No Anthropic API key. Set ENV[\"ANTHROPIC_API_KEY\"], put ANTHROPIC_API_KEY=... in a .env file, or pass `api_key=`."))
    return k
end

"""
    Client(; api_key=nothing, base_url=API_URL, timeout=900, max_retries=5)
"""
struct Client
    api_key::String
    base_url::String
    timeout::Int
    max_retries::Int
end
Client(; api_key=nothing, base_url::AbstractString=API_URL, timeout::Integer=900, max_retries::Integer=5) =
    Client(resolve_api_key(api_key), String(base_url), Int(timeout), Int(max_retries))
Base.show(io::IO, c::Client) = print(io, "Client(", c.base_url, ", key=…", last(c.api_key, 4), ")")

# ---- one request -------------------------------------------------------------------

function parse_api_error(status::Int, body::AbstractString)
    try
        j = JSON.parse(body)
        err = j["error"]
        return AnthropicError(status, String(get(err, "type", "unknown")), String(get(err, "message", body)))
    catch
        return AnthropicError(status, "unknown", String(body))
    end
end

http_timeout_kwargs(seconds) = pkgversion(HTTP) >= v"2" ? (request_timeout=seconds,) : (readtimeout=seconds,)

function retry_delay(resp, attempt::Int)
    ra = HTTP.header(resp, "retry-after", "")
    if !isempty(ra)
        v = tryparse(Float64, ra)
        v === nothing || return min(v, 120.0)
    end
    return min(2.0^attempt + rand(), 60.0)
end

function messages(client::Client, body::AbstractDict; betas::AbstractVector{<:AbstractString}=String[])
    headers = ["content-type" => "application/json", "x-api-key" => client.api_key, "anthropic-version" => API_VERSION]
    isempty(betas) || push!(headers, "anthropic-beta" => join(betas, ","))
    payload = JSON.json(body)
    attempt = 0
    while true
        attempt += 1
        resp = try
            HTTP.post(client.base_url, headers, payload; http_timeout_kwargs(client.timeout)...,
                connect_timeout=30, status_exception=false, retry=false)
        catch e
            e isa InterruptException && rethrow()
            attempt > client.max_retries && rethrow()
            delay = min(2.0^attempt + rand(), 60.0)
            @warn "Anthropic request failed; retrying" attempt delay error = sprint(showerror, e)
            sleep(delay)
            continue
        end
        st = resp.status
        text = String(resp.body)
        if st == 200
            return JSON.parse(text)
        elseif st == 429 || st == 529 || st >= 500
            attempt > client.max_retries && throw(parse_api_error(st, text))
            delay = retry_delay(resp, attempt)
            @warn "Anthropic API returned $st; retrying" attempt delay
            sleep(delay)
        else
            throw(parse_api_error(st, text))
        end
    end
end

function response_text(resp::AbstractDict)
    io = IOBuffer()
    for block in get(resp, "content", Any[])
        get(block, "type", "") == "text" && print(io, block["text"])
    end
    return String(take!(io))
end

function usage_tuple(resp::AbstractDict)
    u = get(resp, "usage", Dict{String,Any}())
    g(k) = something(get(u, k, 0), 0)
    return (input_tokens=g("input_tokens"), output_tokens=g("output_tokens"),
            cache_read_input_tokens=g("cache_read_input_tokens"),
            cache_creation_input_tokens=g("cache_creation_input_tokens"),
            model=String(get(resp, "model", "")))
end

const PRICES = Dict(
    "claude-opus-5"     => (input=5.0,  output=25.0, cache_read=0.5,  cache_write=6.25),
    "claude-opus-4-8"   => (input=5.0,  output=25.0, cache_read=0.5,  cache_write=6.25),
    "claude-sonnet-5"   => (input=2.0,  output=10.0, cache_read=0.2,  cache_write=2.5),
    "claude-haiku-4-5"  => (input=1.0,  output=5.0,  cache_read=0.1,  cache_write=1.25),
    "claude-fable-5-1"  => (input=10.0, output=50.0, cache_read=0.25, cache_write=12.5),
)

function estimate_cost(u::NamedTuple)
    ks = collect(keys(PRICES))
    key = findfirst(k -> startswith(u.model, k), ks)
    p = key === nothing ? PRICES["claude-opus-5"] : PRICES[ks[key]]
    return (u.input_tokens * p.input + u.output_tokens * p.output +
            u.cache_read_input_tokens * p.cache_read + u.cache_creation_input_tokens * p.cache_write) / 1e6
end

"""
    ask_json(client, body; betas) -> (parsed::Dict, resp::Dict)

Send a request whose `output_config.format` is a JSON schema and parse the reply.
"""
function ask_json(client::Client, body::AbstractDict; betas::AbstractVector{<:AbstractString}=String[])
    resp = messages(client, body; betas)
    stop = get(resp, "stop_reason", "")
    if stop == "refusal"
        det = get(resp, "stop_details", nothing)
        error("The model declined the request (stop_reason=refusal): $(det === nothing ? "" : JSON.json(det))")
    end
    stop == "max_tokens" && error("Response truncated at max_tokens=$(body["max_tokens"]); raise `max_tokens`.")
    text = response_text(resp)
    isempty(strip(text)) && error("Empty response from the model (stop_reason=$stop)")
    return JSON.parse(text), resp
end

betas_for(fallbacks::Bool) = fallbacks ? [FALLBACK_BETA] : String[]
