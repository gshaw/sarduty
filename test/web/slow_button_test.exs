defmodule Web.SlowButtonTest do
  @moduledoc """
  A button whose event waits on something slow says so while it waits, with
  phx-disable-with, so a tap never looks like it did nothing and that button cannot be
  sent twice.

  Slow means the event reaches one of @slow: HTTP (D4H, Records, Mapbox, Wallet, email,
  texts), the mailer, a PDF, or signing a pass. The test follows every call and capture in
  the compiled code's debug info, so a helper in another module counts, and a queued job
  or assign_async does not. It misses only a call it cannot see: a module held in a
  variable. Then it checks the button that sends each slow handle_event, in the same
  source file: the phx-click tag, or the submit button of the phx-submit form (#567).
  """
  use ExUnit.Case, async: true

  @root "../.." |> Path.expand(__DIR__)

  # Functions that wait. A function is slow when it calls one of these, or a slow function.
  @slow [{Req, :_}, {App.Mailer, :_}, {Service.LetterPDF, :_}, {System, :cmd}]

  # Req functions that only build a request.
  @not_slow [{Req, :new}, {Req, :merge}]

  # Work these run after the event has answered, so the page shows its own progress.
  # The macros expand to Phoenix.LiveView.Async.
  @async [{Phoenix.LiveView.Async, :assign_async}, {Phoenix.LiveView.Async, :start_async}]

  # Slow events sent by something other than a button in the same file.
  @not_buttons %{
    # Sent by the reply buttons in Web.Components.Reply, which this test reads too.
    {Web.Components.ReplyControl, "reply"} => "lib/web/components/reply.ex"
  }

  test "every button that sends a slow event says what it is doing" do
    graph = call_graph()
    slow = slow_functions(graph)

    missing =
      for {module, event, why} <- slow_events(slow),
          problem <- problems(module, event),
          do: "#{problem}\n  #{event}: #{why}"

    assert missing == [], """
    These buttons wait on something slow but say nothing while they wait. Give each
    phx-disable-with naming the slow thing, like phx-disable-with="Sending…" (docs/writing.md, Slow work):

    #{Enum.join(missing, "\n")}
    """
  end

  defp modules do
    {:ok, modules} = :application.get_key(:sarduty, :modules)
    modules
  end

  # %{{module, name} => [{module, name}]}, every call a function makes, any arity.
  defp call_graph do
    for module <- modules(),
        {{name, _arity}, _kind, _meta, clauses} <- definitions(module),
        reduce: %{} do
      graph ->
        # A clause is {meta, args, guards, body}, a tuple Macro.prewalk/3 does not enter.
        calls = for({_, args, guards, body} <- clauses, do: [args, guards, body])
        calls = calls |> calls(module) |> MapSet.new()
        Map.update(graph, {module, name}, calls, &MapSet.union(&1, calls))
    end
  end

  defp definitions(module) do
    with path when is_list(path) <- :code.which(module),
         {:ok, {_, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(path, [:debug_info]),
         {:ok, %{definitions: definitions}} <- backend.debug_info(:elixir_v1, module, data, []) do
      definitions
    else
      _no_debug_info -> []
    end
  end

  defp calls(ast, module) do
    {_ast, calls} = Macro.prewalk(ast, [], &collect(&1, &2, module))
    calls
  end

  defp collect({{:., _, [callee, name]}, _, _args} = node, acc, _module)
       when is_atom(callee) and is_atom(name),
       do: call(node, {callee, name}, acc)

  # A local or imported capture, &push/1. Its name has no args list.
  defp collect({:&, _, [{:/, _, [{name, meta, ctx}, _arity]}]} = node, acc, module)
       when is_atom(name) and is_atom(ctx),
       do: call(node, {meta[:import] || module, name}, acc)

  # A local call, or an imported one, which keeps its module in the meta.
  defp collect({name, meta, args} = node, acc, module) when is_atom(name) and is_list(args),
    do: call(node, {meta[:import] || module, name}, acc)

  defp collect(node, acc, _module), do: {node, acc}

  # An async call is not followed: :async replaces it, so the walk skips its arguments.
  defp call(node, call, acc),
    do: if(call in @async, do: {:async, acc}, else: {node, [call | acc]})

  # %{function => the slow call it makes}, so a failure can say why a button is slow.
  defp slow_functions(graph) do
    roots =
      for {_function, calls} <- graph,
          {module, _name} = call <- calls,
          {module, :_} in @slow or call in @slow,
          call not in @not_slow,
          into: %{},
          do: {call, nil}

    grow(graph, roots)
  end

  defp grow(graph, slow) do
    more =
      for {function, calls} <- graph,
          not Map.has_key?(slow, function),
          call = Enum.find(calls, &Map.has_key?(slow, &1)),
          into: %{},
          do: {function, call}

    if more == %{}, do: slow, else: grow(graph, Map.merge(slow, more))
  end

  defp why(slow, call) do
    call |> Stream.iterate(&slow[&1]) |> Enum.take_while(& &1) |> Enum.map_join(" → ", &name/1)
  end

  defp name({module, name}), do: "#{inspect(module)}.#{name}"

  # {module, event, why} for each handle_event clause that reaches something slow.
  defp slow_events(slow) do
    for module <- modules(),
        web?(module),
        {{:handle_event, 3}, _kind, _meta, clauses} <- definitions(module),
        {name, body} <- events(clauses),
        call = body |> calls(module) |> Enum.find(&Map.has_key?(slow, &1)),
        uniq: true,
        do: {module, name, why(slow, call)}
  end

  defp events(clauses) do
    for {_meta, [event | _], guards, body} <- clauses,
        name <- event_names(event, guards),
        do: {name, body}
  end

  defp web?(module), do: module |> Module.split() |> hd() == "Web"

  defp event_names(event, _guards) when is_binary(event), do: [event]

  # `when event in [...]` compiles to a chain of event =:= "name".
  defp event_names({var, _, ctx}, guards) when is_atom(var) and is_atom(ctx) do
    {_ast, names} =
      Macro.prewalk(guards, [], fn
        {{:., _, [:erlang, :"=:="]}, _, [{^var, _, _}, name]} = node, acc when is_binary(name) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp event_names(_event, _guards), do: []

  defp problems(module, event) do
    file = @not_buttons[{module, event}] || source(module)
    text = @root |> Path.join(file) |> File.read!()
    clicks = binding_tags(text, "phx-click", event)
    forms = binding_tags(text, "phx-submit", event)

    if clicks == [] and forms == [] do
      ["#{file}: nothing sends \"#{event}\"; say what does in @not_buttons"]
    else
      for({_, tag} <- clicks, not (tag =~ "phx-disable-with"), do: "#{file}: #{squash(tag)}") ++
        for {form, buttons} <- Enum.map(forms, &submit_buttons(text, &1)),
            problem <- form_problems(file, form, buttons),
            do: problem
    end
  end

  defp form_problems(file, form, []), do: ["#{file}: #{squash(form)} has no submit button"]

  defp form_problems(file, _form, buttons),
    do: for(tag <- buttons, not (tag =~ "phx-disable-with"), do: "#{file}: #{squash(tag)}")

  defp source(module) do
    module.module_info(:compile)[:source] |> List.to_string() |> Path.relative_to(@root)
  end

  # The opening tags that bind the event, as "attr=\"event\"" or JS.push("event").
  defp binding_tags(text, attr, event) do
    plain = ~s(#{attr}="#{event}")
    pushed = ~s[#{attr}={JS.push("#{event}"]

    for start <- tag_starts(text),
        tag = tag_at(text, start),
        String.contains?(tag, plain) or String.contains?(tag, pushed),
        do: {start, tag}
  end

  defp tag_starts(text) do
    for [{start, _}] <- Regex.scan(~r/<[.a-z]/, text, return: :index), do: start
  end

  # The tag from its "<" to its closing ">", skipping any ">" inside {…} or quotes.
  defp tag_at(text, start) do
    text |> binary_part(start, byte_size(text) - start) |> take_tag(0, nil, [])
  end

  defp take_tag(<<?>, _::binary>>, 0, nil, acc), do: done([?> | acc])

  defp take_tag(<<c, rest::binary>>, depth, nil, acc) when c in [?", ?'],
    do: take_tag(rest, depth, c, [c | acc])

  defp take_tag(<<c, rest::binary>>, depth, c, acc), do: take_tag(rest, depth, nil, [c | acc])

  defp take_tag(<<?{, rest::binary>>, depth, nil, acc),
    do: take_tag(rest, depth + 1, nil, [?{ | acc])

  defp take_tag(<<?}, rest::binary>>, depth, nil, acc),
    do: take_tag(rest, depth - 1, nil, [?} | acc])

  defp take_tag(<<c, rest::binary>>, depth, quote, acc),
    do: take_tag(rest, depth, quote, [c | acc])

  defp take_tag(<<>>, _depth, _quote, acc), do: done(acc)

  defp done(acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  # The form's submit buttons: inside it up to its closing tag, or outside with form="id".
  defp submit_buttons(text, {start, form}) do
    [_, tag_name] = Regex.run(~r/^<([.\w]+)/, form)
    close = "</#{tag_name}>"
    rest = binary_part(text, start, byte_size(text) - start)
    [inside | _] = String.split(rest, close, parts: 2)
    inside = for {_, tag} <- buttons(inside), submit?(tag), do: tag
    {form, Enum.uniq(inside ++ outside_buttons(text, form))}
  end

  defp outside_buttons(text, form) do
    case Regex.run(~r/\bid="([^"]+)"/, form) do
      [_, id] -> for {_, tag} <- buttons(text), tag =~ ~s(form="#{id}"), do: tag
      nil -> []
    end
  end

  defp buttons(text) do
    for start <- tag_starts(text),
        tag = tag_at(text, start),
        tag =~ ~r/^<\.?button\b/,
        do: {start, tag}
  end

  defp submit?(tag), do: not (tag =~ ~s(type="button")) and not (tag =~ ~r/\b(navigate|href)=/)

  defp squash(tag), do: tag |> String.replace(~r/\s+/, " ") |> String.slice(0, 160)
end
