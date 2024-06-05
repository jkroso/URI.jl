@use "github.com/jkroso/Prospects.jl" @struct Field
@use "./FSPath.jl" FSPath

const regex = r"
  (?:(?<protocol>[^:/?#]+):)?
  (?://)?(?:(?<username>[^/>#@:]+)(?::(?<password>[^/>#@]+))?@)?
  (?<host>[^:/?#\[]*)?
  (?::(?<port>\d{1,5}))?
  (?<path>[^?\#]*)?
  (?:\?(?<query>[^\#]*))?
  (?:\#(?<fragment>.+))?
"x

const empty_query = NamedTuple{(),Tuple{}}([])

@struct struct URI{protocol}
  username::AbstractString=""
  password::AbstractString=""
  host::AbstractString=""
  port::UInt16=UInt16(0)
  path::FSPath=FSPath("")
  query::NamedTuple=empty_query
  fragment::AbstractString=""
end

"""
Parse a URI from a String
"""
URI(uri::AbstractString) = begin
  m = match(regex, uri)
  @assert !isnothing(m) "Invalid URI: '$uri'"
  protocol,user,pass,host,port,path,query,frag = m.captures
  URI{Symbol(isnothing(protocol) ? "" : protocol)}(
    username = isnothing(user) ? "" : decode(user),
    password = isnothing(pass) ? "" : decode(pass),
    host = isnothing(host) ? "" : host,
    port = isnothing(port) ? 0 : parse(UInt16, port),
    path = convert(FSPath, decode(path)),
    query = isnothing(query) ? empty_query : decode_query(m[7]),
    fragment = isnothing(frag) ? "" : frag)
end

Base.getproperty(u::URI, sym::Symbol) = getproperty(u, Field{sym}())
Base.getproperty(u::URI{x}, ::Field{:protocol}) where x = x

function Base.show(io::IO, u::URI)
  write(io, "uri\"")
  print(io, u)
  write(io, '"')
end

const non_hierarchical = Set{Symbol}(Symbol.(split("gopher hdl mailto tel news wais snews sip sips")))

function Base.print(io::IO, u::URI{protocol}) where protocol
  if protocol != Symbol("")
    write(io, protocol, ':')
    isempty(u.username) && isempty(u.host) || protocol in non_hierarchical || write(io,  "//")
  end
  if !isempty(u.username)
    write(io, encode_component(u.username))
    isempty(u.password) || write(io, ':', encode_component(u.password))
    write(io, '@')
  end
  write(io, u.host)
  u.port == 0 || write(io, ':', string(u.port))
  isempty(u.path) || print(io, map(encode_component, u.path))
  isempty(u.query) || write(io, '?', encode_query(u.query))
  isempty(u.fragment) || write(io, '#', u.fragment)
end

"""
Enables shorthand syntax `uri"mailto:pretty@julia"`
"""
macro uri_str(str) URI(str) end

"""
Parse a query string
"""
decode_query(str::AbstractString) = begin
  pairs = split(str, '&'; keepempty=false)
  l = length(pairs)
  keys = Vector{Symbol}(undef, l)
  vals = Vector{String}(undef, l)
  for i in 1:l
    parts = split(pairs[i], "=")
    keys[i] = Symbol(decode(parts[1]))
    vals[i] = length(parts) == 2 ? decode(parts[2]) : ""
  end
  NamedTuple{Tuple(keys), NTuple{l,String}}(vals)
end

"""
Replace hex string excape codes to make the uri readable again
"""
decode(str::AbstractString) = replace(str, hex_regex=>decode_match)
decode_match(hex) = Char(parse(UInt32, hex[2:3], base=16))
const hex_regex = r"%[0-9a-f]{2}"i

"""
Serialize an associative datastructure into a query string
"""
encode_query(data) = join((encode_query(p) for p in pairs(data)), '&')
encode_query(p::Pair) = join(filter!(!isempty, map(encode_component, p)), '=')

const component_blacklist = Set("/=?#:@& []{}")
const blacklist = Set("<>\",;+\$![]'* {}|\\^`" * String(map(Char, 0:31)) * Char(127))

"""
Hex encode characters that would otherwise cause problems in some of the contexts that URI's
are used, such as HTTP requests
"""
encode(str::AbstractString) = replace(str, blacklist=>encode_match)
encode_match(substr) = string('%', uppercase(string(UInt32(substr[1]), base=16, pad=2)))

"""
Hex encode characters that are used as structural delimeters in URI's
"""
encode_component(::Nothing) = ""
encode_component(value) = encode_component(string(value))
encode_component(str::AbstractString) = replace(str, component_blacklist=>encode_match)
