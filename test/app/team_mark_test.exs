defmodule App.TeamMarkTest do
  use ExUnit.Case, async: true

  # Every email and text says whose it is (#857), so a Try a demo team's never goes out
  # by mistake: App.Mailer.deliver/2 raises on an unmarked email, and Twilio's sends take
  # the mark as an argument. This finds the email no test sends: each function that calls
  # Mailer.deliver marks the email in that same function, with for_team/2 or
  # for_no_team/1, where a reader sees it.
  @given_a_marked_email %{
    # SendHelpMessage passes it the email HelpMailer.build/5 made and marked.
    {"lib/app/mailer/help_mailer.ex", :deliver} => true
  }

  test "every function that delivers an email marks it" do
    sends = for path <- Path.wildcard("lib/**/*.ex"), send <- sends(path), do: send

    # Every mailer and the operations that build their own email.
    assert length(sends) >= 10

    unmarked =
      for {path, name, line, marked?} <- sends,
          not marked?,
          not Map.has_key?(@given_a_marked_email, {path, name}),
          do: "#{path}:#{line}: #{name}"

    assert unmarked == [],
           "Pipe the email through Mailer.for_team/2 or Mailer.for_no_team/1 before Mailer.deliver:\n" <>
             Enum.join(unmarked, "\n")
  end

  test "nothing sends a batch around the mark" do
    batches =
      for path <- Path.wildcard("lib/**/*.ex"),
          File.read!(path) =~ ~r/Mailer\.deliver_many/,
          do: path

    assert batches == [], "Mailer.deliver_many skips the mark; deliver one at a time:\n#{batches}"
  end

  # {path, function name, line, marked?} for each def that calls Mailer.deliver.
  defp sends(path) do
    {_ast, defs} =
      path
      |> File.read!()
      |> Code.string_to_quoted!(columns: false)
      |> Macro.prewalk([], fn
        {kind, meta, [head | _body]} = node, acc when kind in [:def, :defp] ->
          if calls?(node, :deliver),
            do: {node, [{path, name(head), meta[:line], marked?(node)} | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    defs
  end

  defp name({:when, _meta, [head | _guards]}), do: name(head)
  defp name({name, _meta, _args}), do: name

  defp marked?(node), do: calls?(node, :for_team) or calls?(node, :for_no_team)

  defp calls?(node, function) do
    {_ast, found?} =
      Macro.prewalk(node, false, fn
        {{:., _, [{:__aliases__, _, aliases}, ^function]}, _, _args} = call, _found
        when aliases in [[:Mailer], [:App, :Mailer]] ->
          {call, true}

        other, found? ->
          {other, found?}
      end)

    found?
  end
end
