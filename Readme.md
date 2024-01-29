# URI.jl

Provides a rich Universal Resource Identifier (URI) type. URI's include a `path` component which can be used separately to navigate your local file system

```julia
@use "github.com/jkroso/URI.jl" @uri_str ["FS.jl" @fs_str]

uri"https://httpbin.org/status/401?a=1#frag".path == fs"/status/401"

fs"/a/b/c"[end] == "c"
fs"/a/b/c"[begin:2] == "/a/b"
fs"/a/b/c" * "d" == "/a/b/c/d"
fs"/a/b/c" * "../d" == "/a/b/d"

@use "github.com/jkroso/Prospects.jl" assoc
assoc(uri"https://httpbin.org", :path, fs"/status/401",
                                :query, (a=1,),
                                :fragment, "frag") == uri"https://httpbin.org/status/401?a=1#frag"
```
