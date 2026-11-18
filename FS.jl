@use "github.com/jkroso/Prospects.jl" Field @field_str @def @abstract
@use "github.com/jkroso/Sequences.jl" EmptySequence Path append
@use "github.com/jkroso/Units.jl" B
@use "./FSPath.jl" FSPath AbsolutePath @fs_str FileType
@use MIMEs: mime_from_extension

# The file system is one tree of objects. Its top is the directory at `/`, and
# every other object is made by the directory that holds it, with `child`. So
# a directory decides what its files and its directories are, and each object
# keeps the directory that made it as its `parent`.
#
# A file's type has the end of its name, like `File{:md}`. A kind of directory
# is a type under `AbstractDirectory`, and a directory of no kind is a
# `Directory`. So a function can have a method for one kind of file, for one
# kind of directory, or for a file in a kind of directory:
#
#     @def struct MailDirectory <: AbstractDirectory end
#     title(d::MailDirectory, f::File{:md}) = "A draft"
#
# A directory gets its kind from `kinds`, by its path:
#
#     kinds[fs"/Users/jake/Mail"] = MailDirectory
#
# A kind of directory says what is in it with a method of `kind`, for its
# directories, or of `child`, for all that it holds:
#
#     kind(::MailDirectory, path::FSPath) = MailDirectory
#
# A kind can have fields of its own, when each has a default. `child` makes a
# directory as `T(path=..., parent=...)`.

"The object at `p`. The directories from `/` down to it make it, each with `child`."
Base.get(p::FSPath) = begin
  @assert p.exists "No FS object $p"
  foldl(child, abs(p), init=root())
end

"An FSObject provides an enhanced interface to each file type"
@abstract struct FSObject
  path::FSPath
  parent::Union{FSObject,Nothing}   # the directory that made it. Only `/` has none.
end

Base.show(io::IO, o::FSObject) = print(io, typeof(o), '(', o.path, ')')

@def struct File{type} <: FSObject end
@def struct SymLink <: FSObject end

"A directory. Each kind of directory is a type under this one."
@abstract struct AbstractDirectory <: FSObject end

"A directory of no kind"
@def struct Directory <: AbstractDirectory end
"The top of the file system: the directory at `/`"
root() = Directory(AbsolutePath(EmptySequence{String}(Path{String})), nothing)

"The kind of each directory that code gave one, by the directory's path. A kind is a type under `AbstractDirectory`."
const kinds = Dict{AbsolutePath,Type{<:AbstractDirectory}}()

"""
The kind of the directory at `path`, which is in `d`: a type under
`AbstractDirectory`. It comes from `kinds`, and a directory that isn't there
is a `Directory`. A kind of directory has a method of this when the
directories in it have a kind too.
"""
kind(d::AbstractDirectory, path::FSPath) = get(kinds, path, Directory)

"""
What `d` holds under `name`. Every object but `/` is made here, so a kind of
directory has a method of this to choose the types of what it holds. A link
shows as what it leads to, and a link that leads nowhere is a `SymLink`.
"""
child(d::AbstractDirectory, name::AbstractString) = begin
  p = typeof(d.path)(append(d.path.path, String(name)))
  ispath(p) || return islink(string(p)) ? SymLink(p, d) : error("No FS object $p")
  t = p.type
  t == FileType.dir && return kind(d, p)(path=p, parent=d)
  t == FileType.file && return File{Symbol(p.extension)}(p, d)
  error("No special type defined for $t")
end

"The file at `path`. The file need not be there yet, but its directory must be."
File(path::FSPath) = begin
  p = abs(path)
  ispath(p) ? get(p)::File : File{Symbol(p.extension)}(p, get(p.parent))
end
File(path::String) = File(FSPath(path))

"The directory at `path`, of whatever kind it is"
AbstractDirectory(path::FSPath) = get(path)::AbstractDirectory
AbstractDirectory(path::String) = AbstractDirectory(FSPath(path))

Base.getproperty(file::File, f::Field{:tags}) = get_file_tags(string(file.path))
Base.getproperty(file::File, f::Field{:size}) = filesize(file.path)B
Base.propertynames(::File) = (:path, :parent, :size, :tags)

Base.read(f::File, args...) = read(f.path, args...)
Base.write(f::File, args...) = write(f.path, args...)
Base.write(f::File{ext}, x) where ext = begin
  m = mime_from_extension(string(ext), MIME("text/plain"))
  write(f.path, sprint(show, m, x))
end

Base.getproperty(d::AbstractDirectory, f::Field{:children}) = map(x->child(d, x), readdir(string(d.path)))
Base.getproperty(d::AbstractDirectory, f::Field{:size}) = sum(field"size", d.children, init=0B)
Base.propertynames(::AbstractDirectory) = (:path, :parent, :children, :size)
Base.dirname(f::File) = f.path.parent
Base.dirname(f::AbstractDirectory) = f.path
Base.isdir(::AbstractDirectory) = true
Base.isdir(::FSObject) = false

Base.islink(::SymLink) = true
Base.islink(::FSObject) = false
Base.isfile(::File) = true
Base.isfile(::FSObject) = false

# Define C types and constants
const libSystem = "libSystem.dylib"  # For getxattr
const libCoreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
const xattr_name = "com.apple.metadata:_kMDItemUserTags"
const kCFAllocatorDefault = C_NULL
const kCFAllocatorNull = C_NULL
const kCFStringEncodingUTF8 = 0x08000100

function get_file_tags(file_path::String)::Vector{String}
  # Step 1: Get size of the extended attribute
  data_size = ccall((:getxattr, libSystem), Cssize_t,
                 (Cstring, Cstring, Ptr{Cvoid}, Csize_t, UInt32, UInt32),
                 file_path, xattr_name, C_NULL, 0, 0, 0)

  data_size <= 0 && return String[]  # No tags

  # Step 2: Allocate buffer and read the extended attribute
  buffer = Vector{UInt8}(undef, data_size)
  data_size = ccall((:getxattr, libSystem), Cssize_t,
                 (Cstring, Cstring, Ptr{UInt8}, Csize_t, UInt32, UInt32),
                 file_path, xattr_name, buffer, data_size, 0, 0)

  if data_size == -1
    error("Failed to read extended attribute for $file_path: $(Base.Libc.strerror())")
  end

  # Step 3: Create CFDataRef (copy the buffer to ensure stability)
  data = ccall((:CFDataCreate, libCoreFoundation), Ptr{Cvoid},
             (Ptr{Cvoid}, Ptr{UInt8}, Csize_t),
             kCFAllocatorDefault, buffer, data_size)

  if data == C_NULL
    error("Failed to create CFData for $file_path")
  end

  # Step 4: Parse the plist
  error_ptr = Ref{Ptr{Cvoid}}(C_NULL)
  plist = ccall((:CFPropertyListCreateWithData, libCoreFoundation), Ptr{Cvoid},
             (Ptr{Cvoid}, Ptr{Cvoid}, UInt32, Ptr{Csize_t}, Ptr{Ptr{Cvoid}}),
             kCFAllocatorDefault, data, 0, C_NULL, error_ptr)

  ccall((:CFRelease, libCoreFoundation), Cvoid, (Ptr{Cvoid},), data)  # Release CFData

  if plist == C_NULL
    if error_ptr[] != C_NULL
        error_desc = ccall((:CFErrorCopyDescription, libCoreFoundation), Ptr{Cvoid},
                          (Ptr{Cvoid},), error_ptr[])
        desc_str = ccall((:CFStringGetCStringPtr, libCoreFoundation), Cstring,
                        (Ptr{Cvoid}, UInt32), error_desc, kCFStringEncodingUTF8)
        error_msg = desc_str != C_NULL ? unsafe_string(desc_str) : "Unknown plist parsing error"
        ccall((:CFRelease, libCoreFoundation), Cvoid, (Ptr{Cvoid},), error_desc)
        ccall((:CFRelease, libCoreFoundation), Cvoid, (Ptr{Cvoid},), error_ptr[])
        error("Failed to parse plist for $file_path: $error_msg")
    else
        error("Failed to parse plist for $file_path")
    end
  end

  # Step 5: Check if plist is a CFArray
  array_type_id = ccall((:CFArrayGetTypeID, libCoreFoundation), Csize_t, ())
  plist_type_id = ccall((:CFGetTypeID, libCoreFoundation), Csize_t, (Ptr{Cvoid},), plist)

  if plist_type_id != array_type_id
    ccall((:CFRelease, libCoreFoundation), Cvoid, (Ptr{Cvoid},), plist)
    error("Plist is not an array for $file_path")
  end

  # Step 6: Extract tags from CFArray
  tags = String[]
  tag_count = ccall((:CFArrayGetCount, libCoreFoundation), Csize_t, (Ptr{Cvoid},), plist)

  for i in 0:(tag_count-1)
    tag = ccall((:CFArrayGetValueAtIndex, libCoreFoundation), Ptr{Cvoid},
               (Ptr{Cvoid}, Csize_t), plist, i)
    string_type_id = ccall((:CFStringGetTypeID, libCoreFoundation), Csize_t, ())
    tag_type_id = ccall((:CFGetTypeID, libCoreFoundation), Csize_t, (Ptr{Cvoid},), tag)

    if tag_type_id == string_type_id
      # Use CFStringGetCStringPtr for simple cases
      cstr = ccall((:CFStringGetCStringPtr, libCoreFoundation), Cstring,
                  (Ptr{Cvoid}, UInt32), tag, kCFStringEncodingUTF8)
      if cstr != C_NULL
        tag_str = unsafe_string(cstr)
        tag_name = split(tag_str, '\n')[1]  # Strip color code
        push!(tags, tag_name)
      else
        # Fallback: Allocate buffer for CFString
        length = ccall((:CFStringGetLength, libCoreFoundation), Csize_t, (Ptr{Cvoid},), tag)
        max_size = length * 4 + 1  # UTF-8 max size
        tag_buffer = Vector{UInt8}(undef, max_size)
        success = ccall((:CFStringGetCString, libCoreFoundation), Cint,
                       (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, UInt32),
                       tag, tag_buffer, max_size, kCFStringEncodingUTF8)
        if success != 0
            tag_str = unsafe_string(pointer(tag_buffer))
            tag_name = split(tag_str, '\n')[1]  # Strip color code
            push!(tags, tag_name)
        end
      end
    end
  end

  # Step 7: Clean up
  ccall((:CFRelease, libCoreFoundation), Cvoid, (Ptr{Cvoid},), plist)

  tags
end
