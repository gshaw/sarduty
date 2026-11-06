defmodule Service.Typst do
  @moduledoc """
  Runs the Typst program to make a PDF (#918). It's a separate program, not a NIF, so
  a crash or a hang can't take down the one machine: a run that takes longer than
  `@timeout_ms` is killed.

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
  """
  def compile(source, files \\ %{}) when is_binary(source) and is_map(files) do
    dir = Service.Temp.path()
    File.mkdir_p!(dir)

    try do
      files
      |> Map.put("main.typ", source)
      |> Enum.each(fn {name, bytes} -> dir |> Path.join(name) |> File.write!(bytes) end)

      output = Path.join(dir, "out.pdf")

      args =
        ["compile", "--root", dir, "--diagnostic-format", "short"] ++
          ["--font-path", fonts_dir(), "--ignore-system-fonts", "--ignore-embedded-fonts"] ++
          ["main.typ", output]

      case run(args, dir) do
        {:ok, ""} -> {:ok, File.read!(output)}
        {:ok, warnings} -> {:error, warnings}
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm_rf(dir)
    end
  end

  def fonts_dir, do: Application.app_dir(:sarduty, "priv/fonts")

  # Typst's output on stdout and stderr together, trimmed, if it exits 0.
  defp run(args, dir) do
    case executable() do
      nil -> {:error, "Typst isn't installed on this server"}
      path -> run_port(path, args, dir)
    end
  end

  defp run_port(path, args, dir) do
    port =
      Port.open({:spawn_executable, path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        cd: dir,
        env: Enum.map(without_environment(), fn {name, nil} -> {to_charlist(name), false} end)
      ])

    # nil when Typst has already exited, as `--version` can before this line.
    os_pid = with {:os_pid, pid} <- Port.info(port, :os_pid), do: pid
    deadline = System.monotonic_time(:millisecond) + @timeout_ms
    collect(port, os_pid, deadline, [])
  end

  defp collect(port, os_pid, deadline, acc) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, os_pid, deadline, [acc, data])

      {^port, {:exit_status, 0}} ->
        {:ok, acc |> IO.iodata_to_binary() |> String.trim()}

      {^port, {:exit_status, status}} ->
        {:error,
         "Typst stopped with status #{status}: #{acc |> IO.iodata_to_binary() |> String.trim()}"}
    after
      left ->
        if os_pid,
          do: System.cmd("kill", ["-9", Integer.to_string(os_pid)], env: without_environment())

        if Port.info(port), do: Port.close(port)
        {:error, "Typst took longer than #{div(@timeout_ms, 1000)} seconds and was stopped"}
    end
  end

  # Typst reads no environment but PATH, so it never sees the server's secrets.
  defp without_environment,
    do: for({name, _value} <- System.get_env(), name != "PATH", do: {name, nil})
end
