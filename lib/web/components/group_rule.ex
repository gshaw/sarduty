defmodule Web.Components.GroupRule do
  @moduledoc """
  A group's rules on its page (#334): the sentence they read as, and the editor, a table
  of rules with a form to add one. The style guide's Build a group rule pattern renders
  the editor with made-up groups and endorsements.

  It takes plain maps, so the guide needs no database. A rule for the sentence is
  `%{kind, names}`, with `names` as `{:group | :endorsement, name}`. An editor row is
  `%{id, kind, names, path, confirm}`, with `names` as text and `confirm` the warning
  before removing it, or nil. `options` are the menu's groups, `{label, [{name, value}]}`.
  """
  use Phoenix.Component

  import Web.Components.A, only: [a: 1]
  import Web.Components.Core, only: [button: 1]
  import Web.Components.Table, only: [table: 1]

  attr :rows, :list, required: true
  attr :options, :list, required: true
  attr :new_path, :string, required: true
  attr :add_confirm, :string, default: nil

  def rule_editor(assigns) do
    ~H"""
    <p class="text-text-muted">
      Members must meet every rule here to be in this group.
    </p>

    <.table :if={@rows != []} id="rules" rows={@rows} row_id={&"rule-#{&1.id}"}>
      <:col :let={row} label="Rule" class="w-px whitespace-nowrap">{kind_label(row.kind)}</:col>
      <:col :let={row} label="Any of">
        <.a navigate={row.path}>{row.names}</.a>
      </:col>
      <:col :let={row} label="" align="right">
        <.button
          size={:sm}
          phx-click="remove-rule"
          phx-value-rule-id={row.id}
          data-confirm={row.confirm}
        >
          Remove
        </.button>
      </:col>
    </.table>

    <form id="add-rule-form" phx-submit="add-rule" class="flex flex-wrap items-center gap-2 mt-4">
      <select name="kind" class="input-sm" aria-label="In or Not in">
        <option value="in">In</option>
        <option value="not_in">Not in</option>
      </select>
      <select name="target" class="input-sm max-w-xs" aria-label="Group or endorsement">
        <option value="">Select a group or endorsement</option>
        {Phoenix.HTML.Form.options_for_select(@options, nil)}
      </select>
      <.button size={:sm} data-confirm={@add_confirm}>Add rule</.button>
      <.a navigate={@new_path}>New endorsement</.a>
    </form>

    <div class="mt-4">
      <.button id="done-editing" variant={:primary} size={:sm} phx-click="done-editing">
        Done
      </.button>
    </div>
    """
  end

  def kind_label(:in), do: "In"
  def kind_label(:not_in), do: "Not in"

  @doc """
  The rules as one sentence, with each name in bold: "Members of GSAR or MIT Callout who
  are not in LOA." or "Members must hold GSAR and First Aid." Names come from users, so
  each is escaped.
  """
  def rule_sentence(rules) do
    case Enum.reject(rules, &(&1.names == [])) do
      [] ->
        "No rules yet."

      [%{kind: :in, names: [{:group, _} | _] = names} = first | rest] ->
        if Enum.all?(names, &match?({:group, _}, &1)),
          do: raw(["Members of ", either(first.names), who(rest), "."]),
          else: must([first | rest])

      rules ->
        must(rules)
    end
  end

  defp must(rules), do: raw(["Members must ", rules |> phrases(&must_phrase/1) |> all(), "."])

  defp who([]), do: []
  defp who(rules), do: [" who ", rules |> phrases(&who_phrase/1) |> all()]

  # One phrase per rule, except In rules that only name endorsements, which share one
  # "hold": "hold GSAR, First Aid, and EMR or OFA 3".
  defp phrases(rules, phrase) do
    {holds, others} = Enum.split_with(rules, &holds_only?/1)

    case holds do
      [] ->
        Enum.map(others, phrase)

      holds ->
        held = %{kind: :in, names: Enum.map(holds, &{:hold_all, &1.names})}
        at = Enum.find_index(rules, &holds_only?/1)
        rules |> Enum.reject(&holds_only?/1) |> List.insert_at(at, held) |> Enum.map(phrase)
    end
  end

  defp holds_only?(%{kind: :in, names: names}), do: endorsements_only?(names)
  defp holds_only?(_rule), do: false

  defp endorsements_only?(names), do: Enum.all?(names, &match?({:endorsement, _}, &1))
  defp groups_only?(names), do: Enum.all?(names, &match?({:group, _}, &1))

  defp must_phrase(%{kind: :in, names: [{:hold_all, _} | _] = names}), do: ["hold ", held(names)]

  defp must_phrase(%{kind: kind, names: names}) do
    {groups, endorsements} = split(names)
    neg = if kind == :not_in, do: "not ", else: ""

    cond do
      groups_only?(names) -> [neg, "be in ", either(groups)]
      endorsements_only?(names) -> [neg, "hold ", either(endorsements)]
      kind == :in -> ["be in ", either(groups), " or hold ", either(endorsements)]
      true -> ["not be in ", either(groups), " and not hold ", either(endorsements)]
    end
  end

  defp who_phrase(%{kind: :in, names: [{:hold_all, _} | _] = names}),
    do: ["also hold ", held(names)]

  defp who_phrase(%{kind: :in, names: names}) do
    case split(names) do
      {groups, []} ->
        ["are also in ", either(groups)]

      {groups, endorsements} ->
        ["are also in ", either(groups), " or hold ", either(endorsements)]
    end
  end

  defp who_phrase(%{kind: :not_in, names: names}) do
    case split(names) do
      {groups, []} ->
        ["are not in ", either(groups)]

      {[], endorsements} ->
        ["don't hold ", either(endorsements)]

      {groups, endorsements} ->
        ["are not in ", either(groups), " and don't hold ", either(endorsements)]
    end
  end

  defp held(names), do: names |> Enum.map(fn {:hold_all, ns} -> either(ns) end) |> all()

  defp split(names),
    do:
      {for({:group, n} <- names, do: {:group, n}),
       for({:endorsement, n} <- names, do: {:endorsement, n})}

  # "A or B": any one will do.
  defp either(names),
    do: names |> Enum.map(fn {_kind, name} -> strong(name) end) |> Enum.intersperse(" or ")

  # "A, B, and C": every one is needed.
  defp all([one]), do: one
  defp all([a, b]), do: [a, " and ", b]

  defp all(many),
    do: [many |> Enum.drop(-1) |> Enum.intersperse(", "), ", and ", List.last(many)]

  defp strong(text),
    do: [
      "<strong>",
      text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string(),
      "</strong>"
    ]

  defp raw(iodata), do: Phoenix.HTML.raw(iodata)
end
