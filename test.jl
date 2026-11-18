@use "github.com/jkroso/Rutherford.jl/test.jl" @test testset @catch
@use "./FSPath.jl" @fs_str FSPath AbsolutePath cwd
@use "./FS.jl" => FS File AbstractDirectory Directory SymLink
@use "github.com/jkroso/Prospects.jl" @def
@use "./main.jl" URI @uri_str encode encode_component decode_query encode_query

@test fs"/a/b/c.md".extension == "md"
@test string(fs"/a/b") == "/a/b"
@test fs"/a" == fs"/a"
@test fs"/a/b/c"*fs"../.././d" == fs"/a/d"
@test fs"/a/b/c"*fs"d" == fs"/a/b/c/d"
@test fs"/a/b/c"[1] == "a"
@test fs"/a/b/" == fs"/a/b/c/"[begin:end-1]
@test fs"/a/b/c"[begin+1:end] == fs"b/c"
@test get(fs"./main.jl").size == filesize("./main.jl")
@test collect(fs"/a/b/c") == ["a", "b", "c"]
@test collect(fs"a/b/c") == ["a", "b", "c"]
@test fs"/a/b/c"[1:3] == fs"/a/b/c"
@test cwd() == FSPath(pwd())
@test abs(fs"./main.jl") == FSPath(pwd() * "/main.jl")
@test abs(fs"main.jl") == FSPath(pwd() * "/main.jl")
@test abs(fs".") == cwd()
@test FSPath(pwd()) * "main.jl" == FSPath(pwd() * "/main.jl")
@test string(fs"~/Desktop") == joinpath(homedir(), "Desktop")
@test fs"a/b/c" ⊆ fs"a"
@test fs"/a/b/c" ⊆ fs"/a"
@test !(fs"/b/b/c" ⊆ fs"/a")
@test !(fs"/b/b/c" ⊆ fs"b")

mktempdir() do tmp
  dir = FSPath(tmp) * "a"
  result = mkdir(dir)
  @test result == dir
  @test result isa AbsolutePath
  dir2 = FSPath(tmp) * "b/c"
  result2 = mkpath(dir2)
  @test result2 == dir2
  @test result2 isa AbsolutePath
end

# What the kinds of directory in the test below say of what they hold
@def struct MailDirectory <: AbstractDirectory end
@def mutable struct NotesDirectory <: AbstractDirectory
  asked::Int=0   # a kind of directory can have fields of its own
end
FS.kind(::MailDirectory, path::FSPath) = MailDirectory
FS.child(d::NotesDirectory, name::AbstractString) =
  endswith(name, ".md") ? File{:note}(d.path * name, d) : invoke(FS.child, Tuple{AbstractDirectory,AbstractString}, d, name)

testset("FS") do
  mktempdir() do tmp
    dir = FSPath(realpath(tmp))
    write(dir * "a.md", "A page")
    mkpath(dir * "mail/Inbox")
    write(dir * "mail/Inbox/1.eml", "An email")
    write(dir * "mail/draft.md", "A draft")
    mkpath(dir * "notes/old")
    write(dir * "notes/b.md", "A note")
    write(dir * "notes/c.txt", "Some text")
    symlink("nowhere", string(dir * "lost"))

    # the top is the directory at `/`, and each object keeps the directory that made it
    top = get(fs"/")
    @test top == FS.root()
    @test top.parent === nothing
    page = get(dir * "a.md")
    @test page isa File{:md}
    @test page.parent == get(dir)
    @test page.parent isa Directory
    up(o) = o.parent === nothing ? o : up(o.parent)
    @test up(page) == top
    @test string(page) == "$(File{:md})($(dir * "a.md"))"

    # a directory is plain until code gives it a kind
    @test get(dir * "mail") isa Directory
    FS.kinds[dir * "mail"] = MailDirectory
    box = get(dir * "mail")
    @test box isa MailDirectory
    @test get(dir * "mail/draft.md").parent == box
    # the kind says that the directories in it are of the kind too
    @test get(dir * "mail/Inbox") isa MailDirectory
    @test get(dir * "mail/Inbox/1.eml") isa File{:eml}
    @test get(dir * "mail/Inbox/1.eml").parent.parent == box
    @test Set(typeof.(box.children)) == Set([MailDirectory, File{:md}])
    # a kind that says nothing of its directories has plain ones
    FS.kinds[dir * "notes"] = NotesDirectory
    @test get(dir * "notes/old") isa Directory
    @test get(dir * "notes") isa NotesDirectory
    @test get(dir * "notes").asked == 0

    # a function can have a method for a file in a kind of directory
    title(d::AbstractDirectory, f::File) = "A page"
    title(d::MailDirectory, f::File{:md}) = "A draft"
    title(f::File) = title(f.parent, f)
    @test title(page) == "A page"
    @test title(get(dir * "mail/draft.md")) == "A draft"

    # a kind of directory can choose the types of all that it holds
    @test get(dir * "notes/b.md") isa File{:note}
    @test get(dir * "notes/c.txt") isa File{:txt}
    @test Set(typeof.(get(dir * "notes").children)) == Set([File{:note}, File{:txt}, Directory])

    # a link that leads nowhere, and a file that isn't written yet
    @test count(c -> c isa SymLink, get(dir).children) == 1
    @test @catch(get(dir * "nothing.md")) isa AssertionError
    new = File(dir * "new.json")
    @test new isa File{:json}
    @test new.parent == get(dir)
    @test File(dir * "notes/b.md") isa File{:note}
    @test AbstractDirectory(dir * "mail") == box

    delete!(FS.kinds, dir * "mail")
    delete!(FS.kinds, dir * "notes")
  end
end

testset("URI") do
  for uri in [
    "hdfs://user:password@hdfs.host:9000/root/folder/file.csv#frag",
    "https://user:password@http.host:9000/path1/path2;paramstring?q=a&p=r#frag",
    "https://user:password@http.host:9000/path1/path2?q=a&p=r#frag",
    "https://user:password@http.host:9000/path1/path2;paramstring#frag",
    "https://user:password@http.host:9000/path1/path2#frag",
    "file:/path/to/file/with%3Fshould%3Dwork%23fine",
    "ftp://ftp.is.co.za/rfc/rfc1808.txt",
    "http://www.ietf.org/rfc/rfc2396.txt",
    # "ldap://[2001:db8::7]/c=GB?objectClass?one", see http://tools.ietf.org/html/rfc3986#section-3.2.2
    "mailto:John.Doe@example.com",
    "news:comp.infosystems.www.servers.unix",
    "tel:+1-816-555-1212",
    "telnet://192.0.2.16:80"]
    # "urn:oasis:names:specification:docbook:dtd:xml:4.1.2"
    @test string(URI(uri)) == uri
  end

  @test ==(URI("hdfs://user:password@hdfs.host:9000/root/folder/file.csv"),
           URI{:hdfs}("user", "password", "hdfs.host", 9000, "/root/folder/file.csv", (;), ""))

  @test URI("//google.com") == URI{Symbol("")}("", "", "google.com", 0, "", (;), "")
  @test uri"//google.com" == URI("//google.com")
  @test string(uri"google.com") == "google.com"
  @test uri"?a=1&b=2".query == (a="1",b="2")

  @test URI("file:/a%20b").path == fs"/a b"
  @test URI("/main.jl")|>string == "/main.jl"
  @test string(URI("/a/b/c", defaults=uri"http://google.com")) == "http://google.com/a/b/c"

  @test decode_query("a&b") == (a="", b="")
  @test decode_query("a=1") == (a="1",)
  @test decode_query("a=1&b=2") == (a="1",b="2")
  @test decode_query("a%2Fb=1%3C2") == (var"a/b"="1<2",)
  @test encode_query(Dict("a"=>"1","b"=>"2")) == "b=2&a=1"
  @test encode_query(Dict("a"=>"","b"=>"")) == "b&a"
  @test encode("http://a.b/>=1 <2.3") == "http://a.b/%3E=1%20%3C2.3"
  @test encode_component("http://a.b/>=1 <2.3") == "http%3A%2F%2Fa.b%2F>%3D1%20<2.3"
  @test uri"imap://a%40gmail.com:mj@imap.gmail.com:993".username == "a@gmail.com"
  @test string(uri"imap://a%40gmail.com:mj@imap.gmail.com:993") == "imap://a%40gmail.com:mj@imap.gmail.com:993"
end
