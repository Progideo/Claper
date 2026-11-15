defmodule ClaperWeb.StaticCacheTest do
  use ClaperWeb.ConnCase

  @immutable "public, max-age=31536000, immutable"

  test "serves gzipped versioned assets with a long-lived cache", %{conn: conn} do
    name = "cache-#{System.unique_integer([:positive])}.js"
    folder = Application.app_dir(:claper, "priv/static/assets")
    File.mkdir_p!(folder)
    asset = Path.join(folder, name)
    contents = "console.log('cache fixture');"
    File.write!(asset, contents)
    File.write!(asset <> ".gz", :zlib.gzip(contents))

    on_exit(fn ->
      File.rm(asset)
      File.rm(asset <> ".gz")
    end)

    path = "/assets/" <> name
    versioned = conn |> put_req_header("accept-encoding", "gzip") |> get(path <> "?vsn=d")
    assert :zlib.gunzip(response(versioned, 200)) == contents
    assert get_resp_header(versioned, "cache-control") == [@immutable]
    assert get_resp_header(versioned, "content-encoding") == ["gzip"]
    assert Enum.map(get_resp_header(versioned, "vary"), &String.downcase/1) == ["accept-encoding"]

    plain = get(conn, path)
    assert response(plain, 200) == contents
    assert get_resp_header(plain, "cache-control") == ["public"]
    assert get_resp_header(plain, "etag") != []

    font = get(conn, "/fonts/Manrope/Manrope.ttf?vsn=d")
    assert font.status == 200
    assert get_resp_header(font, "cache-control") == [@immutable]
  end

  test "caches hashed slide URLs including conditional responses", %{conn: conn} do
    hash = Integer.to_string(System.unique_integer([:positive]))
    folder = Path.join([Application.fetch_env!(:claper, :storage_dir), "uploads", hash])
    File.mkdir_p!(Path.join(folder, "thumbs"))
    File.write!(Path.join(folder, "1.jpg"), "slide image")
    File.write!(Path.join(folder, "thumbs/1.jpg"), "thumbnail")
    on_exit(fn -> File.rm_rf!(folder) end)

    path = "/uploads/#{hash}/1.jpg"
    slide = get(conn, path)
    assert response(slide, 200) == "slide image"
    assert get_resp_header(slide, "cache-control") == [@immutable]
    [etag] = get_resp_header(slide, "etag")

    conditional = conn |> put_req_header("if-none-match", etag) |> get(path)
    assert response(conditional, 304) == ""
    assert get_resp_header(conditional, "cache-control") == [@immutable]

    thumbnail = get(conn, "/uploads/#{hash}/thumbs/1.jpg")
    assert get_resp_header(thumbnail, "cache-control") == ["public"]
    missing = get(conn, "/uploads/#{hash}/2.jpg")
    assert missing.status == 404
    refute @immutable in get_resp_header(missing, "cache-control")
  end
end
