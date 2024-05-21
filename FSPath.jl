@use "github.com/jkroso/Sequences.jl" Cons EmptySequence rest pop Path
@use "github.com/jkroso/Prospects.jl" Field @struct @abstract

"""
A `FSPath` is conceptually a series of strings selecting a part of the FS

```julia
fs"/a/b/c"[1] == "a"
fs"/a/b/c"[3] == "c"
fs"/a/b/c"[begin+1:end] == fs"b/c"
```
"""
@abstract struct FSPath
  path::Path{String}
end

@struct AbsolutePath <: FSPath
@struct RelativePath <: FSPath

macro fs_str(str) convert(FSPath, str) end

Base.convert(::Type{T}, p::AbstractString) where {T<:FSPath} = T(p)
FSPath(str) = isabspath(str) ? AbsolutePath(str) : RelativePath(str)
AbsolutePath(str::AbstractString) = AbsolutePath(convert(Path{String}, splitpath(normpath(str[2:end]))))
RelativePath(str::AbstractString) = RelativePath(convert(Path{String}, splitpath(normpath(str))))

Base.getproperty(p::FSPath, f::Symbol) = getproperty(p, Field{f}())
Base.getproperty(p::FSPath, f::Field{:extension}) = splitext(p.name)[2][2:end]
Base.getproperty(p::FSPath, f::Field{:name}) = p.path.value
Base.getproperty(p::FSPath, f::Field{:parent}) = typeof(p)(pop(p.path))
Base.propertynames(p::FSPath) = (:name, :extension, :parent, :path)

Base.iterate(p::FSPath) = iterate(p, reverse(p.path))
Base.iterate(p::FSPath, seq::Cons{String}) = (seq.head, seq.tail)
Base.iterate(p::FSPath, seq::EmptySequence{Cons{String}}) = nothing
Base.length(p::FSPath) = length(p.path)
Base.lastindex(p::FSPath) = length(p)
Base.firstindex(p::FSPath) = 1
Base.eltype(p::FSPath) = String
Base.isabspath(::RelativePath) = false
Base.isabspath(::AbsolutePath) = true
Base.abs(p::AbsolutePath) = p
Base.abs(p::RelativePath) = cwd()p
cwd() = AbsolutePath(pwd())

Base.:*(a::FSPath, b::AbsolutePath) = b
Base.:*(a::FSPath, b::FSPath) = begin
  ap = a.path
  first(ap) == "." && return b
  bp = b.path
  first(bp) == "." && return a
  for seg in bp
    seg == ".." || break
    ap = pop(ap)
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
