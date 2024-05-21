@use "github.com/jkroso/Prospects.jl" Field @mutable @abstract
@use "./FSPath.jl" FSPath @fs_str

Base.ispath(p::FSPath) = ispath(string(p))
Base.isdir(p::FSPath) = isdir(string(p))
Base.isfile(p::FSPath) = isfile(string(p))
Base.read(p::FSPath, T) = read(string(p), T)
Base.read(p::FSPath) = read(string(p))
Base.write(p::FSPath, x) = write(string(p), x)

Base.get(p::FSPath) = begin
  stat = lstat(string(p))
  @assert ispath(stat) "No FS object $p"
  isdir(stat) && return Directory(p, stat)
  isfile(stat) && return File(p, stat)
  islink(stat) && return SymLink(p, stat)
  error("Unknown FS object type")
end

@abstract struct FSObject
  path::FSPath
  stat::Base.StatStruct
end

Base.getproperty(file::FSObject, f::Symbol) = getproperty(file, Field{f}())
Base.setproperty!(file::FSObject, f::Symbol, x) = setproperty!(file, Field{f}(), x)
Base.getproperty(file::FSObject, f::Field{:parent}) = begin
  stat = lstat(string(file.path))
  Directory(file.path.parent, stat)
end

@mutable File{type} <: FSObject
File(path::FSPath) = File{Symbol(path.extension)}(path, lstat(string(path)))
File(path::FSPath, stat) = File{Symbol(path.extension)}(path, stat)

Base.getproperty(file::File, f::Field{:content}) = read(file.path, String)
Base.setproperty!(file::File, f::Field{:content}, x) = write(file.path, x)

@mutable Directory <: FSObject

Base.getproperty(d::Directory, f::Field{:children}) = map(x->get(d.path*x), readdir(string(d.path)))
Base.propertynames(::Directory) = (:path, :children)

@mutable SymLink <: FSObject
