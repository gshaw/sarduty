defmodule Service.PDFLockTest do
  use ExUnit.Case, async: true

  alias Service.PDFLetter
  alias Service.PDFLock

  # cspell:ignore AESV3 endobj startxref xref -- PDF syntax names
  # cspell:ignore pypdf Tadb Renéʼs -- a Python PDF library, the /Perms marker, test text

  # The pdf package escapes parentheses but not backslashes, so a reader drops the
  # backslash in "\ for", and writes the title's UTF-8 bytes as they are.
  @title "Tax (credit) letter \\ for Renéʼs team (2026"
  @title_as_read "Tax (credit) letter  for Renéʼs team (2026"

  defp letter(extra \\ %{}) do
    %{
      title: @title,
      author: "Treasurer é",
      creator: "SAR Duty",
      logo: nil,
      content: "Dear René’s (friend) \\ backslash\nThanks for volunteering."
    }
    |> Map.merge(extra)
    |> PDFLetter.render()
  end

  defp letter_with_images do
    letter(%{
      logo: File.read!("priv/static/images/logo-sarvac.png"),
      signature: File.read!("priv/apple/sarduty_logo.png"),
      body: "Dear René’s (friend)\nThanks for volunteering.",
      signer: "Jane Doe\nTreasurer"
    })
  end

  # Each stream's data, found by its dictionary's /Length.
  defp streams(pdf) do
    ~r/ 0 obj\n((?:(?!endobj).)*?)\nstream\n/s
    |> Regex.scan(pdf, return: :index)
    |> Enum.map(fn [{_, _}, {dict_start, dict_length}] ->
      dict = binary_part(pdf, dict_start, dict_length)
      [_, length] = Regex.run(~r"/Length (\d+)\n", dict)
      binary_part(pdf, dict_start + dict_length + 8, String.to_integer(length))
    end)
  end

  defp decrypt(key, <<iv::binary-16, data::binary>>),
    do:
      :crypto.crypto_one_time(:aes_256_cbc, key, iv, data, encrypt: false, padding: :pkcs_padding)

  defp hex_entry(pdf, key) do
    [_, hex] = Regex.run(~r"/#{key} <([0-9a-f]+)>", pdf)
    Base.decode16!(hex, case: :lower)
  end

  test "writes a revision 6 AES-256 encryption dictionary and a file ID" do
    locked = PDFLock.lock(letter())

    assert locked =~ ~r/\A%PDF-1\.7\n/
    assert locked =~ "/Filter /Standard\n/V 5\n/R 6\n/Length 256\n"
    assert locked =~ "/CF << /StdCF << /AuthEvent /DocOpen /CFM /AESV3 /Length 32 >> >>"
    assert locked =~ "/StmF /StdCF\n/StrF /StdCF\n"
    assert locked =~ "/P -1340\n/EncryptMetadata true\n"
    assert locked =~ ~r"/Encrypt 7 0 R\n/ID \[<[0-9a-f]{32}> <[0-9a-f]{32}>\]"
    assert byte_size(hex_entry(locked, "U")) == 48
    assert byte_size(hex_entry(locked, "O")) == 48
  end

  test "leaves no plaintext string or stream behind" do
    plain = letter_with_images()
    locked = PDFLock.lock(plain)

    for text <- ["Tax", "credit", "SAR Duty", "Treasurer", "D:2026", "Elixir-PDF"] do
      assert plain =~ text
      refute locked =~ text
    end

    for data <- streams(plain), do: refute(locked =~ data)
  end

  test "points every xref entry at its object and startxref at the table" do
    locked = PDFLock.lock(letter_with_images())

    [_, xref_offset] = Regex.run(~r/startxref\n(\d+)\n%%EOF\n\z/, locked)
    xref_offset = String.to_integer(xref_offset)
    assert binary_part(locked, xref_offset, 5) == "xref\n"

    [_, count] = Regex.run(~r/\Axref\n0 (\d+)\n/, binary_part(locked, xref_offset, 20))
    offsets = Regex.scan(~r/^(\d{10}) 00000 n \n/m, locked, capture: :all_but_first)
    assert length(offsets) == String.to_integer(count) - 1

    offsets
    |> Enum.with_index(1)
    |> Enum.each(fn {[offset], number} ->
      object = "#{number} 0 obj\n"
      assert binary_part(locked, String.to_integer(offset), byte_size(object)) == object
    end)

    assert locked =~ "/Size #{count}\n"
  end

  test "opens with the empty user password and decrypts to the original" do
    plain = letter_with_images()
    locked = PDFLock.lock(plain)

    assert {:ok, key} = PDFLock.file_key(locked)
    assert PDFLock.file_key(locked, "wrong") == :error

    decrypted = locked |> streams() |> Enum.map(&decrypt(key, &1))
    # The logo, its alpha mask, the signature, and the page content.
    assert length(decrypted) == 4
    assert decrypted == streams(plain)
    assert Enum.any?(decrypted, &(:zlib.uncompress(&1) =~ "volunteering"))

    assert decrypt(key, hex_entry(locked, "Title")) == @title_as_read
    assert decrypt(key, hex_entry(locked, "CreationDate")) =~ ~r/\AD:\d{8}\z/
  end

  test "records print-only permissions in /Perms" do
    locked = PDFLock.lock(letter())
    {:ok, key} = PDFLock.file_key(locked)
    perms = :crypto.crypto_one_time(:aes_256_ecb, key, hex_entry(locked, "Perms"), false)

    assert <<p::little-signed-32, 0xFFFFFFFF::32, "Tadb", _random::binary-4>> = perms
    assert p == -1340
    # Print and high-quality print, plus the reserved and accessibility bits.
    assert Bitwise.band(p, 0xFFF) == 0b1010_1100_0100
  end

  test "decodes literal string escapes as a reader does" do
    pdf = """
    %PDF-1.4
    %\xE2\xE3\xCF\xD3
    1 0 obj
    << /Title (a\\(b\\)c \\\\ (nested) \\101\\60\\n\\
    end) /Keywords <48 69> >>
    endobj
    2 0 obj
    << /Type /Catalog >>
    endobj
    xref
    trailer
    << /Size 3 /Root 2 0 R /Info 1 0 R >>
    startxref
    0
    %%EOF
    """

    locked = PDFLock.lock(pdf)
    {:ok, key} = PDFLock.file_key(locked)

    assert locked =~ ~r/\A%PDF-1\.7\n/
    assert decrypt(key, hex_entry(locked, "Title")) == "a(b)c \\ (nested) A0\nend"
    assert decrypt(key, hex_entry(locked, "Keywords")) == "Hi"
  end

  # The expected value comes from pypdf's AlgV5.calculate_hash(6, b"", b"12345678", b"").
  test "matches pypdf's Algorithm 2.B hash" do
    assert "" |> PDFLock.hash_2b("12345678", "") |> Base.encode16() ==
             "EACE262798D0F7325982B486540FF1C118871E1515E59AD3AE35F093A26A54A6"
  end

  test "raises on input that isn't a PDF from the pdf package" do
    assert_raise ArgumentError, ~r/no %PDF/, fn -> PDFLock.lock("hello") end

    assert_raise ArgumentError, ~r/unterminated string/, fn ->
      PDFLock.lock("%PDF-1.7\n%\xE2\n1 0 obj\n<< /Title (open >>\nendobj\n")
    end
  end
end
