defmodule Service.Typst do
  @moduledoc """
  Runs the Typst program to make a PDF (#918), through Service.Program: a run that takes
  longer than `@timeout_ms` is killed.

  It sees only the fonts in `priv/fonts`, never the machine's or its own, so a PDF
  looks the same on a Mac as on Fly. Any warning fails the run: an unknown font
  family is a warning, and a letter shouldn't go out in the wrong font.
  """

  # Keep in step with .mise.toml and the Dockerfile; TypstTest checks all three.
  @version "0.15.1"
  @timeout_ms 20_000

  def version, do: @version

  @doc "The path of the Typst program, or nil when this machine has none."
  def executable, do: System.find_executable("typst")

  @doc "The version the installed Typst reports: `{:ok, \"0.15.1\"}` or `{:error, reason}`."
  def installed_version do
    case run(["--version"], File.cwd!()) do
      {:ok, "typst " <> rest} -> {:ok, rest |> String.split() |> hd()}
      {:ok, other} -> {:error, "typst --version said #{inspect(other)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Makes a PDF from `source`, Typst markup. `files` maps a name to its bytes, for
  images the markup reads by that name. Returns `{:ok, pdf}` or `{:error, reason}`.
  With `png: ppi`, a PNG of its one page at that many pixels an inch instead, as for
  an ID card's sides (#973).
  """
  def compile(source, files \\ %{}, opts \\ []) when is_binary(source) and is_map(files) do
    dir = Service.Temp.path()
    File.mkdir_p!(dir)

    try do
      write_files(dir, Map.put(files, "main.typ", source))
      {output, format_args} = output(dir, Keyword.get(opts, :png))

      case dir |> args(format_args, output) |> run(dir) do
        {:ok, ""} -> {:ok, File.read!(output)}
        {:ok, warnings} -> {:error, warnings}
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm_rf(dir)
    end
  end

  defp write_files(dir, files),
    do: Enum.each(files, fn {name, bytes} -> dir |> Path.join(name) |> File.write!(bytes) end)

  defp args(dir, format_args, output),
    do:
      ["compile", "--root", dir, "--diagnostic-format", "short"] ++
        ["--font-path", fonts_dir(), "--ignore-system-fonts", "--ignore-embedded-fonts"] ++
        format_args ++ ["main.typ", output]

  # A PDF, or with `png: ppi` a PNG at that many pixels an inch.
  defp output(dir, nil), do: {Path.join(dir, "out.pdf"), []}
  defp output(dir, ppi), do: {Path.join(dir, "out.png"), ["--ppi", to_string(ppi)]}

  def fonts_dir, do: Application.app_dir(:sarduty, "priv/fonts")

  # Typst's output on stdout and stderr together, trimmed, if it exits 0. It reads no
  # environment but PATH, so it never sees the server's secrets.
  defp run(args, dir), do: Service.Program.run(executable(), args, dir, "Typst", @timeout_ms)
end
