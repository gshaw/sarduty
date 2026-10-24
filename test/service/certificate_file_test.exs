defmodule Service.CertificateFileTest do
  use ExUnit.Case, async: true

  import App.DataFixtures, only: [png_fixture: 2]

  alias Service.CertificateFile
  alias Vix.Vips.MutableImage

  # cspell:ignore gchararray ftypheic -- libvips's string type, and a HEIC file's first bytes

  # A JPEG with the photographer's name in its EXIF, as a phone adds GPS and the camera.
  defp jpeg_with_exif(width, height) do
    {:ok, image} = Image.new(width, height, color: :steelblue)

    {:ok, image} =
      Image.mutate(image, fn mutable ->
        MutableImage.set(mutable, "exif-ifd0-Artist", :gchararray, "Sam Rivera")
      end)

    {:ok, jpeg} = Image.write(image, :memory, suffix: ".jpg", strip_metadata: false)
    assert {:ok, %{artist: "Sam Rivera"}} = jpeg |> Image.from_binary!() |> Image.exif()
    jpeg
  end

  # A 4 × 4 PNG whose header claims `width` × `height` pixels.
  # cspell:ignore IHDR -- the PNG header chunk, which holds the size
  defp png_claiming(width, height) do
    <<signature::binary-8, length::32, "IHDR", _width::32, _height::32, rest::binary-5, _crc::32,
      tail::binary>> = png_fixture(4, 4)

    header = <<"IHDR", width::32, height::32, rest::binary>>
    <<signature::binary, length::32, header::binary, :erlang.crc32(header)::32, tail::binary>>
  end

  test "the type comes from the first bytes, not the name" do
    assert CertificateFile.type("%PDF-1.7\n") == :pdf
    assert 4 |> png_fixture(4) |> CertificateFile.type() == :image
    assert CertificateFile.type(<<0, 0, 0, 24, "ftypheic", 0, 0>>) == :heic
    assert CertificateFile.type("<html><script>") == :unknown
  end

  test "a PDF is kept as it came" do
    assert CertificateFile.prepare("%PDF-1.7 bytes", "first-aid.pdf") ==
             {:ok,
              %{
                bytes: "%PDF-1.7 bytes",
                content_type: "application/pdf",
                file_name: "first-aid.pdf"
              }}
  end

  test "a photo becomes a JPEG up to 2000 px, without its metadata" do
    assert {:ok, file} = 3000 |> jpeg_with_exif(1500) |> CertificateFile.prepare("IMG_2041.HEIC")
    assert %{content_type: "image/jpeg", file_name: "IMG_2041.jpg"} = file

    image = file.bytes |> Image.from_binary!()
    assert {Image.width(image), Image.height(image)} == {2000, 1000}
    assert {:error, _no_exif} = Image.exif(image)
  end

  test "a PNG is flattened to a JPEG" do
    assert {:ok, %{content_type: "image/jpeg", bytes: <<0xFF, 0xD8, _rest::binary>>}} =
             40 |> png_fixture(30) |> CertificateFile.prepare("scan.png")
  end

  test "anything else, or too big, is refused" do
    assert {:error, "Choose a photo or a PDF."} = CertificateFile.prepare("<svg/>", "x.pdf")

    assert {:error, "SAR Duty cannot read this photo. Send it as a JPEG."} =
             CertificateFile.prepare(<<0, 0, 0, 24, "ftypheic", 0::size(64)>>, "IMG.HEIC")

    big = "%PDF-" <> :binary.copy("x", CertificateFile.max_bytes())
    assert {:error, "Choose a file under 10 MB."} = CertificateFile.prepare(big, "big.pdf")
  end

  test "a photo claiming more pixels than any phone takes is refused before it is decoded" do
    bomb = png_claiming(40_000, 40_000)
    assert byte_size(bomb) < 1000

    assert CertificateFile.prepare(bomb, "scan.png") ==
             {:error, "SAR Duty cannot read a photo this large. Select a smaller photo or a PDF."}
  end
end
