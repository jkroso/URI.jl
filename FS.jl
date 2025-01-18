@use "github.com/jkroso/Prospects.jl" Field @mutable @abstract
@use "./FSPath.jl" FSPath @fs_str FileType

Base.get(p::FSPath) = begin
  @assert p.exists "No FS object $p"
  t = p.type
  t == FileType.dir && return Directory(p)
  t == FileType.file && return File(p)
  t == FileType.link && return SymLink(p)
  error("No special type defined for $t")
end

"An FSObject provides an enhanced interface to each file type"
@abstract struct FSObject
  path::FSPath
end

Base.getproperty(file::FSObject, f::Symbol) = getproperty(file, Field{f}())
Base.setproperty!(file::FSObject, f::Symbol, x) = setproperty!(file, Field{f}(), x)
Base.getproperty(file::FSObject, f::Field{:parent}) = Directory(file.path.parent)

@mutable File{type} <: FSObject
File(path::FSPath) = File{Symbol(path.extension)}(path)

Base.getproperty(file::File, f::Field{:content}) = read(file.path, String)
Base.setproperty!(file::File, f::Field{:content}, x) = write(file.path, x)

@mutable Directory <: FSObject

Base.getproperty(d::Directory, f::Field{:children}) = map(x->get(d.path*x), readdir(string(d.path)))
Base.propertynames(::Directory) = (:path, :children)

@mutable SymLink <: FSObject
