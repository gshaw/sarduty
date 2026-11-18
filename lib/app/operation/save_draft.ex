defmodule App.Operation.SaveDraft do
  @moduledoc """
  Saved AI turns (#1089): a person's unsaved changes to a report or a form, with AI
  writing's conversation, kept after every ask and every hand edit
  (App.Model.AIDraft). Change report and Change form call `call/5` after each, and it
  decides whether there's anything to keep; `open/2` brings a draft back when the page
  opens, and `discard/2` is Start over, Discard them, and a save.

  A subject is a `%Form{}`, or `{team, report}` for a report, `report` nil for a new one.
  Only its author ever opens a draft: every function takes the user.

  A form's PDFs go in the file store (docs/files.md), one file per PDF by its SHA-256,
  never the form's saved page, which stays in form_pages. The row names them, so Undo
  can put back the PDF from before an ask.
  """

  alias App.Accounts.User
  alias App.Adapter.FileStore
  alias App.Model.AIDraft
  alias App.Model.Form
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Repo

  # Each ask's keys, as the pages keep them. Only these come back as atoms.
  @ask_keys ~w(id ask before before_page page test? note undo? blank next failed)a
  # The keys of a failed ask's words and of each label left blank.
  @failed_keys ~w(title detail again?)a
  @blank_keys ~w(label why)a
  # An ask's PDFs, kept by their SHA-256.
  @page_keys ~w(before_page page)a

  @doc """
  Keeps the page's `fields` and `asks` as the user's draft of `subject`, or discards
  the draft when there's nothing to keep (`keep?/3`). A form's `fields` are `text` and
  `page`, its PDF's bytes; a report's are `name`, `about`, `query`, and `values`. `asks`
  is the conversation, newest first, each PDF as its bytes.

  `{:ok, draft}`, `{:ok, nil}` when nothing is kept, or `{:error, reason}` when the file
  store refused a PDF, which leaves the draft as it was.
  """
  def call(%User{} = user, subject, fields, asks, now \\ DateTime.utc_now()) do
    if keep?(subject, fields, asks) do
      keep(user, subject, fields, asks, now)
    else
      discard(user, subject)
      {:ok, nil}
    end
  end

  @doc """
  Whether there's anything to keep: a change from what's saved, or a conversation. A
  new report is kept once AI has answered an ask.
  """
  def keep?(%Form{} = form, fields, asks),
    do: asks != [] or fields["text"] != form.text or page_sha(fields) != form.page_sha256

  def keep?({%Team{}, %SavedReport{} = report}, fields, asks),
    do: asks != [] or Map.take(fields, ~w(name about query)) != report_fields(report)

  def keep?({%Team{}, nil}, _fields, asks), do: Enum.any?(asks, &(!&1[:failed]))

  defp report_fields(report),
    do: Map.new(~w(name about query), &{&1, Map.get(report, String.to_existing_atom(&1)) || ""})

  defp page_sha(%{"page" => page}) when is_binary(page), do: Form.sha256(page)
  defp page_sha(_fields), do: nil

  defp keep(user, subject, fields, asks, now) do
    draft = AIDraft.get(user, subject) || AIDraft.new(user, subject)
    {fields, asks, pages} = encode(fields, asks)
    pages = Map.reject(pages, fn {sha, _bytes} -> saved_page?(subject, sha) end)
    token = draft.files_token || if(pages != %{}, do: FileStore.new_token())

    with :ok <- put_pages(draft, token, pages) do
      kept =
        draft
        |> Ecto.Changeset.change(
          fields: fields,
          asks: asks,
          pages: Map.keys(pages),
          files_token: token,
          updated_at: now
        )
        |> Repo.insert_or_update!()

      delete_pages(kept, draft.pages -- kept.pages)
      {:ok, kept}
    end
  end

  defp saved_page?(%Form{page_sha256: sha}, sha), do: true
  defp saved_page?(_subject, _sha), do: false

  # Each PDF not kept yet; the first the store refuses stops the save.
  defp put_pages(draft, token, pages) do
    pages
    |> Enum.reject(fn {sha, _bytes} -> sha in draft.pages end)
    |> Enum.reduce_while(:ok, fn {sha, bytes}, :ok ->
      case FileStore.put(key(draft, token, sha), bytes, "application/pdf") do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp delete_pages(draft, shas),
    do: Enum.each(shas, &FileStore.delete(key(draft, draft.files_token, &1)))

  defp key(%AIDraft{organization_id: id}, token, sha) when is_integer(id),
    do: FileStore.key(:orgs, id, :form_draft, token, "#{sha}.pdf")

  defp key(%AIDraft{team_id: id}, token, sha),
    do: FileStore.key(:teams, id, :form_draft, token, "#{sha}.pdf")

  @doc """
  `{fields, asks, pages}`: the page's fields and conversation as the row keeps them,
  each PDF as its SHA-256, and `pages`, every PDF by its SHA-256.
  """
  def encode(fields, asks) do
    {fields, pages} = encode_page(fields, "page", %{})

    {asks, pages} =
      Enum.map_reduce(asks, pages, fn ask, pages ->
        Enum.reduce(@page_keys, {Map.take(ask, @ask_keys), pages}, fn key, {ask, pages} ->
          encode_page(ask, key, pages)
        end)
      end)

    {fields, asks, pages}
  end

  defp encode_page(map, key, pages) do
    case Map.get(map, key) do
      bytes when is_binary(bytes) ->
        sha = Form.sha256(bytes)
        {Map.put(map, key, sha), Map.put(pages, sha, bytes)}

      _none ->
        {map, pages}
    end
  end

  @doc """
  The user's draft of `subject`, as the page keeps it, or nil: `%{fields, asks, at}`,
  where `at` is when it was last kept. Each ask has a new id, and a form's PDFs are
  bytes again. A PDF the store no longer has is the form's saved one.
  """
  def open(%User{} = user, subject) do
    case AIDraft.get(user, subject) do
      nil -> nil
      draft -> decode(draft, load_pages(draft, subject), saved_page(subject))
    end
  end

  defp load_pages(draft, subject) do
    saved = saved_page(subject)

    stored =
      Map.new(draft.pages, fn sha ->
        case FileStore.get(key(draft, draft.files_token, sha)) do
          {:ok, bytes} -> {sha, bytes}
          {:error, _reason} -> {sha, saved}
        end
      end)

    case subject do
      %Form{page_sha256: sha} when is_binary(sha) -> Map.put(stored, sha, saved)
      _report -> stored
    end
  end

  defp saved_page(%Form{} = form), do: Form.page_bytes(form)
  defp saved_page(_report), do: nil

  @doc """
  The draft's fields and asks as the page keeps them, from the row and its PDFs by
  SHA-256 (`pages`). A PDF not in `pages`, such as a saved page since replaced, is
  `saved`, the form's page now.
  """
  def decode(%AIDraft{} = draft, pages, saved \\ nil) do
    pages = Map.put(pages, :saved, saved)
    fields = decode_page(draft.fields, "page", pages)

    asks =
      Enum.map(draft.asks, fn ask ->
        ask
        |> atomize(@ask_keys)
        |> Map.put(:id, System.unique_integer([:positive]))
        |> Map.update(:failed, nil, &(&1 && atomize(&1, @failed_keys)))
        |> Map.update(:blank, [], fn blank -> Enum.map(blank || [], &atomize(&1, @blank_keys)) end)
        |> then(fn ask -> Enum.reduce(@page_keys, ask, &decode_page(&2, &1, pages)) end)
      end)

    %{fields: fields, asks: asks, at: draft.updated_at}
  end

  defp decode_page(map, key, pages) do
    case Map.fetch(map, key) do
      {:ok, sha} when is_binary(sha) -> Map.put(map, key, Map.get(pages, sha, pages.saved))
      _none -> map
    end
  end

  # Only the keys named, so a row never makes a new atom.
  defp atomize(map, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Map.fetch(map, Atom.to_string(key)) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  @doc "Discards the user's draft of `subject`, if any, with its PDFs. Always `:ok`."
  def discard(%User{} = user, subject) do
    case AIDraft.get(user, subject) do
      nil -> :ok
      draft -> delete(draft)
    end
  end

  @doc "Discards every person's draft of `form`, with their PDFs, as the form goes."
  def discard_all(%Form{} = form), do: form |> AIDraft.all_for_form() |> Enum.each(&delete/1)

  @doc "Discards drafts unchanged for 30 days, with their PDFs. Returns how many."
  def prune(now) do
    expired = AIDraft.expired(now)
    Enum.each(expired, &delete/1)
    length(expired)
  end

  defp delete(draft) do
    Repo.delete!(draft)
    delete_pages(draft, draft.pages)
    :ok
  end
end
