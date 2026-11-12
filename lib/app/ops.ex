defmodule App.Ops do
  @moduledoc """
  Runs a task for `bin/prod` and records it (docs/production.md). `bin/prod` calls
  `main/1` over `bin/sarduty rpc` with the request as base64 JSON, so no argument needs
  quoting. Every run that reaches a task, failed ones too, is a `prod_task` event: who,
  the agent if one ran it, the task, its arguments, why, the rows, and the outcome.
  Never the output, which can name members.
  """

  alias App.Accounts
  alias App.Accounts.User
  alias App.Model.Event

  # A new task is a module in lib/app/ops/ and a line here.
  @tasks [App.Ops.Query, App.Ops.Jobs, App.Ops.MakeAdmin, App.Ops.RestoreTeam]

  # bin/prod prints only what's between these, so Fly's and the VM's own lines stay out.
  @start "--- bin/prod ---"
  @ok "--- ok ---"
  @failed "--- failed ---"

  @cell_length 80

  @doc "The entry point for `bin/prod`: decodes the request, runs it, and prints the result."
  def main(encoded) when is_binary(encoded) do
    {status, lines} =
      with {:ok, json} <- Base.decode64(encoded),
           {:ok, request} <- Jason.decode(json) do
        run(request)
      else
        _ -> {:error, ["The request from bin/prod didn't decode."]}
      end

    output =
      [@start | lines]
      |> Enum.concat([if(status == :ok, do: @ok, else: @failed)])
      |> Enum.join("\n")

    # Printing is the point: rpc hands it back to bin/prod.
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(output)
  end

  @doc """
  Runs one request: `task`, `args`, `fix` (true when asked as `bin/prod fix`), `email`,
  `via` and `why`. Returns `{:ok, lines}` or `{:error, lines}`.
  """
  def run(%{"task" => "list"}), do: {:ok, list_lines()}

  def run(%{"task" => name} = request) when is_binary(name) do
    args = List.wrap(request["args"])

    with {:ok, task} <- find(name, request["fix"] == true),
         {:ok, why} <- why(request["why"]),
         {:ok, user} <- admin(request["email"]) do
      run_task(%{task: task, args: args, why: why, via: request["via"], user: user})
    end
  end

  def run(_request), do: {:error, ["Name a task. bin/prod list shows them."]}

  defp run_task(%{task: task, args: args} = run) do
    started = System.monotonic_time(:millisecond)
    result = call(task, args)
    ms = System.monotonic_time(:millisecond) - started
    record!(run, result, ms)
    lines(result, ms)
  end

  defp list_lines do
    width = @tasks |> Enum.map(&String.length(&1.usage())) |> Enum.max()
    Enum.map(@tasks, &"#{String.pad_trailing(&1.usage(), width)}  #{&1.summary()}")
  end

  defp find(name, fix?) do
    case Enum.find(@tasks, &(&1.name() == name)) do
      nil -> {:error, ["No task called #{name}. bin/prod list shows them."]}
      task -> check_verb(task, fix?)
    end
  end

  defp check_verb(task, fix?) do
    cond do
      task.write?() and not fix? ->
        {:error, ["#{task.name()} changes data: bin/prod fix #{task.name()}"]}

      fix? and not task.write?() ->
        {:error, ["#{task.name()} only reads: bin/prod #{task.name()}"]}

      true ->
        {:ok, task}
    end
  end

  defp why(why) when is_binary(why) do
    case String.trim(why) do
      "" -> {:error, ["Say why with --why: an issue number or a sentence."]}
      why -> {:ok, String.slice(why, 0, 200)}
    end
  end

  defp why(_why), do: why("")

  # Who ran it is self-declared, as with any shell; the token is the boundary. This names
  # the person in the record.
  defp admin(email) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      %User{is_admin: true} = user ->
        {:ok, user}

      _ ->
        {:error,
         [
           "#{email} isn't a SAR Duty admin. Set yours with: git config sarduty.email you@example.org"
         ]}
    end
  end

  defp admin(_email),
    do:
      {:error,
       ["bin/prod sent no email. Set yours with: git config sarduty.email you@example.org"]}

  defp call(task, args) do
    task.run(args)
  rescue
    error -> {:error, error |> Exception.message() |> first_line()}
  catch
    kind, reason -> {:error, kind |> Exception.format_banner(reason) |> first_line()}
  end

  defp record!(%{task: task, user: user} = run, result, ms) do
    {outcome, rows, error} =
      case result do
        {:ok, %{rows: rows}} -> {"ok", length(rows), nil}
        {:ok, _line} -> {"ok", nil, nil}
        {:error, line} -> {"failed", nil, line}
      end

    data =
      run
      |> Map.take([:args, :why, :via])
      |> Map.merge(%{task: task.name(), outcome: outcome, rows: rows, error: error})
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    Event.record!(:prod_task, user_id: user.id, duration_ms: ms, data: data)
  end

  defp lines({:ok, %{columns: columns, rows: rows} = table}, ms) do
    count = rows |> length() |> Service.Format.count(one: "%d row", many: "%d rows")
    summary = "#{count} in #{Service.Format.run_time(ms)}, recorded"
    {:ok, Enum.concat([table_lines(columns, rows), List.wrap(table[:note]), [summary]])}
  end

  defp lines({:ok, line}, ms),
    do: {:ok, [line, "Done in #{Service.Format.run_time(ms)}, recorded"]}

  defp lines({:error, line}, ms),
    do: {:error, [line, "Failed after #{Service.Format.run_time(ms)}, recorded"]}

  defp table_lines(columns, rows) do
    cells = Enum.map([columns | rows], fn row -> Enum.map(row, &cell/1) end)

    widths =
      Enum.zip_with(cells, fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)

    Enum.map(cells, fn row ->
      row
      |> Enum.zip_with(widths, &String.pad_trailing/2)
      |> Enum.join("  ")
      |> String.trim_trailing()
    end)
  end

  defp cell(nil), do: "NULL"
  defp cell(value) when is_number(value) or is_atom(value), do: to_string(value)

  defp cell(value) when is_binary(value) do
    if String.printable?(value), do: short(value), else: "<#{byte_size(value)} bytes>"
  end

  defp cell(value), do: value |> inspect() |> short()

  defp short(text) do
    text = String.replace(text, ~r/\s+/, " ")

    if String.length(text) > @cell_length,
      do: String.slice(text, 0, @cell_length - 1) <> "…",
      else: text
  end

  defp first_line(text), do: text |> String.split("\n", parts: 2) |> hd() |> String.slice(0, 200)
end
