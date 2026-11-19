defmodule Service.Program do
  @moduledoc """
  Runs a separate program, such as Typst (#918) or MuPDF's mutool (#1083), not a NIF, so
  a crash or a hang can't take down the one machine: a run that takes longer than its
  timeout is killed. The program sees no environment but PATH, so never the server's
  secrets.
  """

  @doc """
  The program's output on stdout and stderr together, trimmed, as `{:ok, output}` when it
  exits 0, or `{:error, reason}`. `name` is how a reason names it.
  """
  def run(nil, _args, _dir, name, _timeout_ms),
    do: {:error, "#{name} isn't installed on this server"}

  def run(path, args, dir, name, timeout_ms) do
    port =
      Port.open({:spawn_executable, path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        cd: dir,
        env: Enum.map(without_environment(), fn {key, nil} -> {to_charlist(key), false} end)
      ])

    # nil when the program has already exited, as `--version` can before this line.
    os_pid = with {:os_pid, pid} <- Port.info(port, :os_pid), do: pid
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    collect(port, os_pid, deadline, {name, timeout_ms}, [])
  end

  defp collect(port, os_pid, deadline, {name, timeout_ms} = about, acc) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, os_pid, deadline, about, [acc, data])

      {^port, {:exit_status, 0}} ->
        {:ok, acc |> IO.iodata_to_binary() |> String.trim()}

      {^port, {:exit_status, status}} ->
        {:error,
         "#{name} stopped with status #{status}: #{acc |> IO.iodata_to_binary() |> String.trim()}"}
    after
      left ->
        if os_pid,
          do: System.cmd("kill", ["-9", Integer.to_string(os_pid)], env: without_environment())

        if Port.info(port), do: Port.close(port)
        {:error, "#{name} took longer than #{div(timeout_ms, 1000)} seconds and was stopped"}
    end
  end

  defp without_environment,
    do: for({name, _value} <- System.get_env(), name != "PATH", do: {name, nil})
end
