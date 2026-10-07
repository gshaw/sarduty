defmodule Service.PDFLock do
  @moduledoc """
  Encrypts a PDF with AES-256 (security handler revision 6) so it opens with no password
  but allows only printing. It rewrites the output of the `pdf` package and raises on
  anything else; it is not a general PDF parser.

  The lock is honour-system: Acrobat and most readers respect it, but unlock tools strip it.
  """

  # cspell:ignore AESV3 endobj endstream startxref xref -- PDF syntax names

  # Print (bit 3) and high-quality print (bit 12). Bits 7, 8, and 13-32 are reserved and
  # must be 1. Bit 10 (accessibility) is deprecated in PDF 2.0, and writers must set it.
  @permissions Bitwise.bor(0xFFFFF000, 0b1010_1100_0100)
  @signed_permissions @permissions - 0x1_0000_0000

  @whitespace [0, ?\t, ?\n, ?\f, ?\r, ?\s]
  @delimiters [?(, ?), ?<, ?>, ?[, ?], ?{, ?}, ?/, ?%]

  @doc "Returns `pdf`, a document from the `pdf` package, encrypted print-only."
  def lock(pdf) when is_binary(pdf) do
    {version, rest} = read_header(pdf)
    {objects, trailer} = read_objects(rest, [])
    check_numbering!(objects)

    file_key = :crypto.strong_rand_bytes(32)
    owner_password = :crypto.strong_rand_bytes(32)
    encrypt_number = length(objects) + 1
    header = <<"%PDF-", version::binary, "\n%", 0xE2, 0xE3, 0xCF, 0xD3, "\r\n">>
    {body, offsets} = write_objects(header, objects, file_key)

    offsets = [{encrypt_number, IO.iodata_length(body)} | offsets]
    body = [body | encrypt_object(encrypt_number, file_key, owner_password)]
    xref_offset = IO.iodata_length(body)

    IO.iodata_to_binary([
      body,
      xref(offsets),
      write_trailer(trailer, encrypt_number, xref_offset)
    ])
  end

  defp write_objects(header, objects, file_key) do
    Enum.reduce(objects, {[header], []}, fn object, {body, offsets} ->
      offset = IO.iodata_length(body)
      {[body | write_object(object, file_key)], [{object.number, offset} | offsets]}
    end)
  end

  @doc false
  # Recovers the file key from /U and /UE with the user password, as a reader does.
  def file_key(locked_pdf, password \\ "") do
    [_, u] = Regex.run(~r"/U <([0-9a-f]{96})>", locked_pdf)
    [_, ue] = Regex.run(~r"/UE <([0-9a-f]{64})>", locked_pdf)

    <<hash::binary-32, validation_salt::binary-8, key_salt::binary-8>> =
      Base.decode16!(u, case: :lower)

    if hash_2b(password, validation_salt, "") == hash do
      key = hash_2b(password, key_salt, "")
      {:ok, aes_256_cbc_no_iv(key, Base.decode16!(ue, case: :lower), false)}
    else
      :error
    end
  end

  @doc false
  # Algorithm 2.B of ISO 32000-2, the hash behind every revision 6 key and check value.
  def hash_2b(password, salt, user_key) do
    password = binary_part(password, 0, min(byte_size(password), 127))
    hash_2b_round(password, user_key, :crypto.hash(:sha256, [password, salt, user_key]), 0)
  end

  defp hash_2b_round(password, user_key, k, round) do
    <<key::binary-16, iv::binary-16, _::binary>> = k
    k1 = :binary.copy(password <> k <> user_key, 64)
    e = :crypto.crypto_one_time(:aes_128_cbc, key, iv, k1, true)
    <<first::binary-16, _::binary>> = e
    hash = Enum.at([:sha256, :sha384, :sha512], first |> byte_sum() |> rem(3))
    k = :crypto.hash(hash, e)
    round = round + 1

    if round >= 64 and :binary.last(e) <= round - 32 do
      binary_part(k, 0, 32)
    else
      hash_2b_round(password, user_key, k, round)
    end
  end

  defp byte_sum(bytes), do: for(<<byte <- bytes>>, reduce: 0, do: (sum -> sum + byte))

  defp read_header(<<"%PDF-", major, ?., minor, ?\n, ?%, rest::binary>>)
       when major in ?1..?2 and minor in ?0..?9 do
    [_comment, rest] = :binary.split(rest, "\n")
    # AES-256 is PDF 2.0, or 1.7 with Adobe's extension; readers accept a 1.7 header.
    {max(<<major, ?., minor>>, "1.7"), rest}
  end

  defp read_header(_pdf), do: raise(ArgumentError, "not a PDF: no %PDF-1.x header")

  defp read_objects(pdf, objects) do
    case Regex.run(~r/\A\s*(?:(\d+) 0 obj\s|xref\s)/, pdf, return: :index) do
      [{0, length}, {start, digits}] ->
        number = pdf |> binary_part(start, digits) |> String.to_integer()
        rest = binary_part(pdf, length, byte_size(pdf) - length)
        {object, rest} = read_object(number, rest)
        read_objects(rest, [object | objects])

      [{0, _length}] ->
        {Enum.reverse(objects), read_trailer(pdf)}

      nil ->
        raise ArgumentError, "unexpected PDF content: #{inspect(binary_slice(pdf, 0, 40))}"
    end
  end

  defp read_object(number, pdf) do
    case scan(pdf, []) do
      {tokens, "endobj", rest} ->
        {%{number: number, tokens: tokens, stream: nil}, rest}

      {tokens, "stream", rest} ->
        length = stream_length(tokens, number)

        case skip_eol(rest) do
          <<data::binary-size(^length), rest::binary>> -> end_stream(number, tokens, data, rest)
          _ -> raise ArgumentError, "object #{number}: PDF ends inside the stream"
        end

      {_tokens, keyword, _rest} ->
        raise ArgumentError, "object #{number}: unexpected #{inspect(keyword)}"
    end
  end

  defp end_stream(number, tokens, data, rest) do
    case Regex.run(~r/\A\s*endstream\s+endobj/, rest, return: :index) do
      [{0, end_length}] ->
        rest = binary_part(rest, end_length, byte_size(rest) - end_length)
        {%{number: number, tokens: tokens, stream: data}, rest}

      nil ->
        raise ArgumentError, "object #{number}: stream data doesn't match its /Length"
    end
  end

  defp skip_eol("\r\n" <> rest), do: rest
  defp skip_eol("\n" <> rest), do: rest
  defp skip_eol(_), do: raise(ArgumentError, "no end of line after stream")

  defp read_trailer(pdf) do
    with [_xref, after_xref] <- :binary.split(pdf, "trailer"),
         {tokens, "startxref", _rest} <- scan(after_xref, []) do
      values = Enum.reject(tokens, &match?({:space, _}, &1))
      %{root: reference!(values, "Root"), info: reference(values, "Info")}
    else
      _ -> raise ArgumentError, "no trailer dictionary before startxref"
    end
  end

  defp reference(values, key) do
    values
    |> Enum.chunk_every(4, 1)
    |> Enum.find_value(fn
      [{:name, ^key}, {:word, number}, {:word, "0"}, {:word, "R"}] -> number
      _ -> nil
    end)
  end

  defp reference!(values, key) do
    reference(values, key) || raise ArgumentError, "trailer has no /#{key} reference"
  end

  defp check_numbering!(objects) do
    numbers = Enum.map(objects, & &1.number)

    if Enum.sort(numbers) != Enum.to_list(1..length(numbers)//1) do
      raise ArgumentError, "expected objects numbered 1 to #{length(numbers)}"
    end
  end

  # Splits object syntax into tokens up to the keyword that ends it: stream, endobj, or
  # startxref. Literal strings come back decoded so they can be encrypted.
  defp scan(<<>>, _tokens), do: raise(ArgumentError, "PDF ends inside an object")

  defp scan(<<c, _::binary>> = pdf, tokens) when c in @whitespace do
    {space, rest} = take_while(pdf, &(&1 in @whitespace))
    scan(rest, [{:space, space} | tokens])
  end

  defp scan("(" <> rest, tokens) do
    {string, rest} = literal_string(rest, 0, [])
    scan(rest, [{:string, string} | tokens])
  end

  defp scan("<<" <> rest, tokens), do: scan(rest, [:open | tokens])
  defp scan(">>" <> rest, tokens), do: scan(rest, [:close | tokens])

  defp scan("<" <> rest, tokens) do
    [hex, rest] = :binary.split(rest, ">")
    hex = String.replace(hex, ~r/\s/, "")
    hex = if rem(byte_size(hex), 2) == 1, do: hex <> "0", else: hex
    scan(rest, [{:string, Base.decode16!(hex, case: :mixed)} | tokens])
  end

  defp scan(<<c, rest::binary>>, tokens) when c in [?[, ?]],
    do: scan(rest, [{:space, <<c>>} | tokens])

  defp scan("/" <> rest, tokens) do
    {name, rest} = take_while(rest, &(&1 not in @whitespace and &1 not in @delimiters))
    scan(rest, [{:name, name} | tokens])
  end

  defp scan(<<c, _::binary>> = pdf, tokens) when c not in @delimiters do
    {word, rest} = take_while(pdf, &(&1 not in @whitespace and &1 not in @delimiters))

    if word in ["stream", "endobj", "startxref"],
      do: {Enum.reverse(tokens), word, rest},
      else: scan(rest, [{:word, word} | tokens])
  end

  defp scan(<<c, _::binary>>, _tokens),
    do: raise(ArgumentError, "unexpected #{inspect(<<c>>)} in PDF object")

  defp take_while(binary, keep?) do
    length =
      Enum.find(0..(byte_size(binary) - 1)//1, byte_size(binary), fn index ->
        not keep?.(:binary.at(binary, index))
      end)

    {binary_part(binary, 0, length), binary_part(binary, length, byte_size(binary) - length)}
  end

  # Decodes a literal string body as a reader would (ISO 32000-1 7.3.4.2), after the "(".
  defp literal_string(<<>>, _depth, _acc), do: raise(ArgumentError, "unterminated string")

  defp literal_string(")" <> rest, 0, acc),
    do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp literal_string(")" <> rest, depth, acc), do: literal_string(rest, depth - 1, [")" | acc])
  defp literal_string("(" <> rest, depth, acc), do: literal_string(rest, depth + 1, ["(" | acc])
  defp literal_string("\r\n" <> rest, depth, acc), do: literal_string(rest, depth, ["\n" | acc])
  defp literal_string("\r" <> rest, depth, acc), do: literal_string(rest, depth, ["\n" | acc])

  defp literal_string("\\" <> rest, depth, acc) do
    {bytes, rest} = escape(rest)
    literal_string(rest, depth, [bytes | acc])
  end

  defp literal_string(<<c, rest::binary>>, depth, acc),
    do: literal_string(rest, depth, [c | acc])

  defp escape("n" <> rest), do: {"\n", rest}
  defp escape("r" <> rest), do: {"\r", rest}
  defp escape("t" <> rest), do: {"\t", rest}
  defp escape("b" <> rest), do: {"\b", rest}
  defp escape("f" <> rest), do: {"\f", rest}
  defp escape("\r\n" <> rest), do: {"", rest}
  defp escape("\r" <> rest), do: {"", rest}
  defp escape("\n" <> rest), do: {"", rest}

  defp escape(<<a, b, c, rest::binary>>) when a in ?0..?7 and b in ?0..?7 and c in ?0..?7,
    do: {<<rem(String.to_integer(<<a, b, c>>, 8), 256)>>, rest}

  defp escape(<<a, b, rest::binary>>) when a in ?0..?7 and b in ?0..?7,
    do: {<<String.to_integer(<<a, b>>, 8)>>, rest}

  defp escape(<<a, rest::binary>>) when a in ?0..?7, do: {<<a - ?0>>, rest}
  # Covers \( \) \\, and drops the backslash before any other character.
  defp escape(<<c, rest::binary>>), do: {<<c>>, rest}
  defp escape(<<>>), do: raise(ArgumentError, "unterminated string")

  defp stream_length(tokens, number) do
    case length_value(tokens, 0) do
      {:ok, length} -> length
      :error -> raise ArgumentError, "object #{number}: stream has no direct /Length"
    end
  end

  defp length_value([], _depth), do: :error
  defp length_value([:open | rest], depth), do: length_value(rest, depth + 1)
  defp length_value([:close | rest], depth), do: length_value(rest, depth - 1)

  defp length_value([{:name, "Length"}, {:space, _}, {:word, word} | rest], 1) do
    case Integer.parse(word) do
      {length, ""} -> {:ok, length}
      _ -> length_value(rest, 1)
    end
  end

  defp length_value([_ | rest], depth), do: length_value(rest, depth)

  defp put_length([], _depth, _length), do: []

  defp put_length([:open | rest], depth, length),
    do: [:open | put_length(rest, depth + 1, length)]

  defp put_length([:close | rest], depth, length),
    do: [:close | put_length(rest, depth - 1, length)]

  defp put_length([{:name, "Length"} = name, space, {:word, _} | rest], 1, length),
    do: [name, space, {:word, Integer.to_string(length)} | rest]

  defp put_length([token | rest], depth, length), do: [token | put_length(rest, depth, length)]

  defp write_object(%{stream: nil} = object, key) do
    ["#{object.number} 0 obj\n", write_tokens(object.tokens, key), "endobj\n"]
  end

  defp write_object(object, key) do
    data = aes_256_cbc(key, object.stream)
    tokens = put_length(object.tokens, 0, byte_size(data))

    [
      "#{object.number} 0 obj\n",
      write_tokens(tokens, key),
      "stream\n",
      data,
      "\nendstream\nendobj\n"
    ]
  end

  defp write_tokens(tokens, key) do
    Enum.map(tokens, fn
      {:space, space} -> space
      :open -> "<<"
      :close -> ">>"
      {:name, name} -> ["/", name]
      {:word, word} -> word
      {:string, string} -> hex(aes_256_cbc(key, string))
    end)
  end

  # Algorithms 8, 9, and 10 of ISO 32000-2: the /U /UE /O /OE /Perms entries.
  defp encrypt_object(number, file_key, owner_password) do
    user_password = ""
    user_salts = :crypto.strong_rand_bytes(16)
    <<user_validation::binary-8, user_key_salt::binary-8>> = user_salts
    u = hash_2b(user_password, user_validation, "") <> user_salts
    ue = aes_256_cbc_no_iv(hash_2b(user_password, user_key_salt, ""), file_key, true)

    owner_salts = :crypto.strong_rand_bytes(16)
    <<owner_validation::binary-8, owner_key_salt::binary-8>> = owner_salts
    o = hash_2b(owner_password, owner_validation, u) <> owner_salts
    oe = aes_256_cbc_no_iv(hash_2b(owner_password, owner_key_salt, u), file_key, true)

    perms_block =
      <<@permissions::little-32, 0xFFFFFFFF::32, "T", "adb">> <> :crypto.strong_rand_bytes(4)

    perms = :crypto.crypto_one_time(:aes_256_ecb, file_key, perms_block, true)

    """
    #{number} 0 obj
    <<
    /Filter /Standard
    /V 5
    /R 6
    /Length 256
    /CF << /StdCF << /AuthEvent /DocOpen /CFM /AESV3 /Length 32 >> >>
    /StmF /StdCF
    /StrF /StdCF
    /O #{hex(o)}
    /U #{hex(u)}
    /OE #{hex(oe)}
    /UE #{hex(ue)}
    /Perms #{hex(perms)}
    /P #{@signed_permissions}
    /EncryptMetadata true
    >>
    endobj
    """
  end

  defp xref(offsets) do
    entries =
      offsets
      |> Enum.sort()
      |> Enum.map(fn {_number, offset} ->
        [offset |> Integer.to_string() |> String.pad_leading(10, "0"), " 00000 n \n"]
      end)

    ["xref\n0 #{length(offsets) + 1}\n0000000000 65535 f \n", entries]
  end

  defp write_trailer(trailer, encrypt_number, xref_offset) do
    id = :crypto.strong_rand_bytes(16)
    info = if trailer.info, do: "/Info #{trailer.info} 0 R\n", else: ""

    """
    trailer
    <<
    /Size #{encrypt_number + 1}
    /Root #{trailer.root} 0 R
    #{info}/Encrypt #{encrypt_number} 0 R
    /ID [#{hex(id)} #{hex(id)}]
    >>
    startxref
    #{xref_offset}
    %%EOF
    """
  end

  # AES-256-CBC with a random IV in front and PKCS#7 padding, for strings and streams.
  defp aes_256_cbc(key, data) do
    iv = :crypto.strong_rand_bytes(16)

    iv <>
      :crypto.crypto_one_time(:aes_256_cbc, key, iv, data, encrypt: true, padding: :pkcs_padding)
  end

  defp aes_256_cbc_no_iv(key, data, encrypt?),
    do: :crypto.crypto_one_time(:aes_256_cbc, key, <<0::128>>, data, encrypt?)

  defp hex(bytes), do: "<" <> Base.encode16(bytes, case: :lower) <> ">"
end
