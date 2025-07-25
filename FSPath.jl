@use "github.com/jkroso/Prospects.jl" Field @struct @abstract ["BitSet.jl" @BitSet] ["Enum.jl" @Enum]
@use "github.com/jkroso/Sequences.jl" Sequence EmptySequence rest pop Path

"""
| **Bit** | **Description**     |
|---------|---------------------|
| 0       | Others - Execute    |
| 1       | Others - Write      |
| 2       | Others - Read       |
| 3       | Group - Execute     |
| 4       | Group - Write       |
| 5       | Group - Read        |
| 6       | Owner - Execute     |
| 7       | Owner - Write       |
| 8       | Owner - Read        |
| 9       | Sticky Bit          |
| 10      | Set Group ID (SGID) |
| 11      | Set User ID (SUID)  |
| 12      | 4 bit file type     |
| 13      | 4 bit file type     |
| 14      | 4 bit file type     |
| 15      | 4 bit file type     |
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
Base.getproperty(p::FSPath, f::Field{:children}) = readdir(p)
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
Base.open(p::FSPath, mode) = open(string(p), mode)
Base.open(p::FSPath) = open(string(p))
Base.ispath(p::FSPath) = ispath(string(p))
Base.isdir(p::FSPath) = isdir(string(p))
Base.isfile(p::FSPath) = isfile(string(p))
Base.rm(p::FSPath; kwargs...) = rm(string(p); kwargs...)
Base.mv(src::FSPath, dest::FSPath; kwargs...) = FSPath(mv(string(src), string(dest); kwargs...))
Base.cp(src::FSPath, dest::FSPath; kwargs...) = FSPath(cp(string(src), string(dest); kwargs...))
Base.cd(fn, dir::FSPath) = cd(fn, string(dir))
Base.eachline(path::FSPath; kwargs...) = eachline(string(path); kwargs...)
Base.readline(path::FSPath; kwargs...) = readline(string(path); kwargs...)
Base.readuntil(path::FSPath, delim; kwargs...) = readuntil(string(path), delim; kwargs...)
Base.dirname(p::FSPath) = p.parent
Base.basename(p::FSPath) = p.path.value
Base.joinpath(a::FSPath, b) = a * b
Base.relpath(a::FSPath, b::FSPath) = relpath(abs(a), abs(b))
Base.relpath(a::AbsolutePath, b::AbsolutePath) = begin
  ap = a.path
  bp = b.path
  while !isempty(ap) && !isempty(bp)
    segA = first(ap)
    segB = first(bp)
    segA != segB && return RelativePath(cat(convert(Path{String}, fill("..", length(ap))), bp))
    ap = rest(ap)
    bp = rest(bp)
  end
  RelativePath(bp)
end
Base.readdir(p::FSPath) = [joinpath(p, n) for n in readdir(string(p))]
Base.filesize(p::FSPath) = filesize(string(p))
Base.stat(p::FSPath) = stat(string(p))
Base.mkdir(p::FSPath; mode=FileMode(0o755)) = mkdir(string(p); mode=convert(UInt32, mode))
Base.mkpath(p::FSPath; mode=FileMode(0o755)) = mkpath(string(p); mode=convert(UInt32, mode))

Base.chmod(p::FSPath, mode::Integer) = chmod(string(p), mode)
if Sys.isunix()
  Base.chown(p::FSPath, uid::Integer, gid::Integer) = chown(string(p), uid, gid)
end

Base.readlink(p::FSPath) = FSPath(readlink(string(p)))
Base.realpath(p::FSPath) = AbsolutePath(realpath(string(p)))
Base.mtime(p::FSPath) = mtime(string(p))
Base.ctime(p::FSPath) = ctime(string(p))

Base.issubset(a::T, b::T) where T<:FSPath = all(x->isequal(x[1], x[2]), zip(a,b)) && length(a) >= length(b)
