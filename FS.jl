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
Base.getproperty(file::File, f::Field{:tags}) = get_file_tags(string(file.path))
Base.setproperty!(file::File, f::Field{:content}, x) = write(file.path, x)

@mutable Directory <: FSObject

Base.getproperty(d::Directory, f::Field{:children}) = map(x->get(d.path*x), readdir(string(d.path)))
Base.propertynames(::Directory) = (:path, :children)

@mutable SymLink <: FSObject

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
