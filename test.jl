@require "github.com/jkroso/Rutherford.jl/test.jl" @test testset
@use "./FSPath.jl" @fs_str FSPath cwd
@use "./FS.jl"
@use "./main.jl" URI @uri_str encode encode_component decode_query encode_query

@test fs"/a/b/c.md".extension == "md"
@test string(fs"/a/b") == "/a/b"
@test fs"/a" == fs"/a"
@test fs"/a/b/c"*fs"../.././d" == fs"/a/d"
@test fs"/a/b/c"*fs"d" == fs"/a/b/c/d"
@test fs"/a/b/c"[1] == "a"
@test fs"/a/b/" == fs"/a/b/c/"[begin:end-1]
@test fs"/a/b/c"[begin+1:end] == fs"b/c"
@test get(fs"./main.jl").content == String(read("./main.jl"))
@test collect(fs"/a/b/c") == ["a", "b", "c"]
@test collect(fs"a/b/c") == ["a", "b", "c"]
@test fs"/a/b/c"[1:3] == fs"/a/b/c"
@test cwd() == FSPath(pwd())
@test abs(fs"./main.jl") == FSPath(pwd() * "/main.jl")
@test abs(fs"main.jl") == FSPath(pwd() * "/main.jl")
@test abs(fs".") == cwd()
@test FSPath(pwd()) * "main.jl" == FSPath(pwd() * "/main.jl")
@test string(abs(fs"~/Desktop")) == joinpath(homedir(), "Desktop")

testset("URI") do
  for url in [
    "hdfs://user:password@hdfs.host:9000/root/folder/file.csv#frag",
    "https://user:password@http.host:9000/path1/path2;paramstring?q=a&p=r#frag",
    "https://user:password@http.host:9000/path1/path2?q=a&p=r#frag",
    "https://user:password@http.host:9000/path1/path2;paramstring#frag",
    "https://user:password@http.host:9000/path1/path2#frag",
    "file:/path/to/file/with%3fshould%3dwork%23fine",
    "ftp://ftp.is.co.za/rfc/rfc1808.txt",
    "http://www.ietf.org/rfc/rfc2396.txt",
    # "ldap://[2001:db8::7]/c=GB?objectClass?one", see http://tools.ietf.org/html/rfc3986#section-3.2.2
    "mailto:John.Doe@example.com",
    "news:comp.infosystems.www.servers.unix",
    "tel:+1-816-555-1212",
    "telnet://192.0.2.16:80",
    "urn:oasis:names:specification:docbook:dtd:xml:4.1.2"
  ]
    u = URI(url)
    string(u) == url
    @test isvalid(u)
  end

  @test ==(URI("hdfs://user:password@hdfs.host:9000/root/folder/file.csv"),
           URI{:hdfs}("user", "password", "hdfs.host", 9000, "/root/folder/file.csv", (;), ""))

  @test !isvalid(URI("file:///path/to/file/with?should=work#fine"))
  @test  isvalid(URI("file:///path/to/file/with%3fshould%3dwork%23fine"))

  @test URI("//google.com") == URI{Symbol("")}("", "", "google.com", 0, "", (;), "")
  @test uri"//google.com" == URI("//google.com")
  @test string(uri"google.com") == "google.com"
  @test uri"?a=1&b=2".query == (a="1",b="2")

  @test URI("file:/a%20b").path == "/a b"
  @test URI("/main.jl")|>string == "/main.jl"

  @test decode_query("a&b") == (a="", b="")
  @test decode_query("a=1") == (a="1",)
  @test decode_query("a=1&b=2") == (a="1",b="2")
  @test decode_query("a%2Fb=1%3C2") == Dict("a/b"=>"1<2")
  @test encode_query(Dict("a"=>"1","b"=>"2")) == "b=2&a=1"
  @test encode_query(Dict("a"=>"","b"=>"")) == "b&a"
  @test encode("http://a.b/>=1 <2.3") == "http://a.b/%3E=1%20%3C2.3"
  @test encode_component("http://a.b/>=1 <2.3") == "http%3A%2F%2Fa.b%2F>%3D1%20<2.3"
end
