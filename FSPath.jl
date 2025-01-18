@use "github.com/jkroso/Sequences.jl" Sequence EmptySequence rest pop Path
@use "github.com/jkroso/Prospects.jl" Field @struct @abstract ["BitSet.jl" @BitSet] ["Enum.jl" @Enum]

"""
15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  └── Others - Execute
 |  |  |  |  |  |  |  |  |  |  |  |  |  |  └───── Others - Write
 |  |  |  |  |  |  |  |  |  |  |  |  |  └──────── Others - Read
 |  |  |  |  |  |  |  |  |  |  |  |  └─────────── Group - Execute
 |  |  |  |  |  |  |  |  |  |  |  └────────────── Group - Write
 |  |  |  |  |  |  |  |  |  |  └───────────────── Group - Read
 |  |  |  |  |  |  |  |  |  └──────────────────── Owner - Execute
 |  |  |  |  |  |  |  |  └─────────────────────── Owner - Write
 |  |  |  |  |  |  |  └────────────────────────── Owner - Read
 |  |  |  |  |  |  └───────────────────────────── Sticky Bit
 |  |  |  |  |  └──────────────────────────────── Set Group ID (SGID)
 |  |  |  |  └─────────────────────────────────── Set User ID (SUID)
 |  |  |  └────────────────────────────────────── 4bit file type encoding
 |  |  └───────────────────────────────────────── 4bit file type encoding
 |  └──────────────────────────────────────────── 4bit file type encoding
 └─────────────────────────────────────────────── 4bit file type encoding
"""
@BitSet FileMode OX OW OR GE GW GR E W R sticky GID UID
@Enum FileType file dir socket chardev link block

"""
A `FSPath` is conceptually a series of strings selecting a part of the FS

```julia
fs"/a/b/c"[1] == "a"
fs"/a/b/c"[3] == "c"
fs"/a/b/c"[begin+1:end] == fs"b/c"
```
"""
@abstract struct FSPath
  path::Sequence{String}
end

@struct AbsolutePath <: FSPath
@struct RelativePath <: FSPath

macro fs_str(str::String)
  if occursin('$', str)
    expr = Meta.parse(":(\"$(escape_string(str))\")").args[1]
    :(convert(FSPath, $(esc(expr))))
  else
    convert(FSPath, str)
  end
end

Base.convert(::Type{T}, p::AbstractString) where {T<:FSPath} = T(p)
FSPath(str) = begin
  isempty(str) && return RelativePath(EmptySequence{String}(Path{String}))
  startswith(str, "~") && return home()*RelativePath(str[3:end])
  isabspath(str) ? AbsolutePath(str) : RelativePath(str)
end

AbsolutePath(str::AbstractString) = AbsolutePath(convert(Path{String}, segments(str[2:end])))
RelativePath(str::AbstractString) = RelativePath(convert(Path{String}, segments(str)))

segments(str) = begin
  str = normpath(str)
  str == "." && return []
  splitpath(str)
end

Base.getproperty(p::FSPath, f::Symbol) = getproperty(p, Field{f}())
Base.getproperty(p::FSPath, f::Field{:extension}) = splitext(p.name)[2][2:end]
Base.getproperty(p::FSPath, f::Field{:name}) = p.path.value
Base.getproperty(p::FSPath, f::Field{:parent}) = typeof(p)(pop(p.path))
Base.getproperty(p::FSPath, f::Field{:exists}) = ispath(string(p))
Base.getproperty(p::FSPath, f::Field{:type}) = FileType(bitreverse((filemode(string(p))>>8%UInt8)&0xf0))
Base.getproperty(p::FSPath, f::Field{:mode}) = FileMode(filemode(string(p)) & 0x0fff)
Base.propertynames(p::FSPath) = (:name, :extension, :parent, :path, :exists, :type, :mode)

Base.iterate(p::FSPath) = iterate(p, p.path)
Base.iterate(p::FSPath, seq::Sequence) = (first(seq), rest(seq))
Base.iterate(p::FSPath, seq::EmptySequence) = nothing
Base.length(p::FSPath) = length(p.path)
Base.lastindex(p::FSPath) = length(p)
Base.firstindex(p::FSPath) = 1
Base.eltype(p::FSPath) = String
Base.isabspath(::RelativePath) = false
Base.isabspath(::AbsolutePath) = true
Base.abs(p::AbsolutePath) = p
Base.abs(p::RelativePath) = cwd()p
Base.map(f::Function, p::FS) where FS<:FSPath = FS(map(f, p.path))

home() = AbsolutePath(homedir())
cwd() = AbsolutePath(pwd())

Base.:*(a::FSPath, b::AbsolutePath) = b
Base.:*(a::FSPath, b::FSPath) = begin
  ap = a.path
  bp = b.path
  for seg in bp
    seg == ".." || break
    ap = isempty(ap) ? ap : pop(ap)
    bp = rest(bp)
  end
  typeof(a)(cat(ap, bp))
end
Base.:*(a::FSPath, b::AbstractString) = a*convert(FSPath, b)

Base.getindex(p::FSPath, i::Integer) = begin
  l = length(p)
  @assert 0 < i <= l "Attempted to get index $i from a Path with $l segments"
  p.path[i]
end
Base.getindex(p::RelativePath, range::UnitRange) = RelativePath(p.path[range])
Base.getindex(p::AbsolutePath, range::UnitRange) = (range.start == 1 ? AbsolutePath : RelativePath)(p.path[range])

Base.show(io::IO, p::FSPath) = begin
  isabspath(p) && write(io, '/')
  join(io, p.path, '/')
  nothing
end

Base.show(io::IO, ::MIME"text/html", p::FSPath) = begin
  write(io, "<div>$p</div>")
  nothing
end

Base.read(p::FSPath, T) = read(string(p), T)
Base.read(p::FSPath) = read(string(p))
Base.write(p::FSPath, x) = write(string(p), x)
Base.ispath(p::FSPath) = ispath(string(p))
Base.isdir(p::FSPath) = isdir(string(p))
Base.isfile(p::FSPath) = isfile(string(p))
