@use "github.com/jkroso/Prospects.jl" @struct Field
@use "./FSPath.jl" FSPath

const regex = r"
  (?:([A-Za-z-+\.]+):)?  # protocol
  (?://)?
  (?:
    ([\w.]+)             # username
    (?::(\w+))?          # password
    @
  )?
  ([\w-]+(?:\.[\w-]+)*)? # host
  (?::(\d{1,5}))?        # port
  ([^?\#]*)?             # path
  (?:\?([^\#]*))?        # query
  (?:\#(.+))?            # fragment
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
  m = match(regex, uri).captures
  URI{Symbol(isnothing(m[1]) ? "" : m[1])}(
    username = isnothing(m[2]) ? "" : m[2],
    password = isnothing(m[3]) ? "" : m[3],
    host = isnothing(m[4]) ? "" : m[4],
    port = isnothing(m[5]) ? 0 : parse(UInt16,m[5]),
    path = convert(FSPath, decode(m[6])),
    query = isnothing(m[7]) ? empty_query : decode_query(m[7]),
    fragment = isnothing(m[8]) ? "" : m[8])
end

Base.getproperty(u::URI, sym::Symbol) = getproperty(u, Field{sym}())
Base.getproperty(u::URI{x}, ::Field{:protocol}) where x = x

function Base.show(io::IO, u::URI)
  write(io, "uri\"")
  print(io, u)
  write(io, '"')
end

function Base.print(io::IO, u::URI{protocol}) where protocol
  if protocol != Symbol("")
    write(io, protocol, ':')
    string(protocol) in non_hierarchical || write(io,  "//")
  end
  if !isempty(u.username)
    write(io, u.username)
    isempty(u.password) || write(io, ':', u.password)
    write(io, '@')
  end
  write(io, u.host)
  u.port == 0 || write(io, ':', string(u.port))
  print(io, u.path)
  isempty(u.query) || write(io, '?', encode_query(u.query))
  isempty(u.fragment) || write(io, '#', u.fragment)
end

const uses_authority = Set{String}(split("hdfs ftp http gopher nntp telnet imap wais file mms https shttp snews
                                          prospero rtsp rtspu rsync svn svn+ssh sftp nfs git git+ssh ldap mailto"))
const uses_params = Set{String}(split("ftp hdl prospero http imap https shttp rtsp rtspu sip sips mms sftp tel"))
const non_hierarchical = Set{String}(split("gopher hdl mailto news telnet wais imap snews sip sips"))
const uses_query = Set{String}(split("http wais imap https shttp mms gopher rtsp rtspu sip sips ldap"))
const uses_fragment = Set{String}(split("hdfs ftp hdl http gopher news nntp wais https shttp snews file prospero"))

function Base.isvalid(uri::URI{protocol}) where protocol
  s = string(protocol)
  s in non_hierarchical && occursin('/', uri.path) && return false # path hierarchy not allowed
  s in uses_query || isempty(uri.query) || return false            # query component not allowed
  s in uses_fragment || isempty(uri.fragment) || return false      # fragment identifier component not allowed
  s in uses_authority && return true
  return isempty(uri.username) && isempty(uri.password)            # authority component not allowed
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
