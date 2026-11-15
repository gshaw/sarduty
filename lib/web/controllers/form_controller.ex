defmodule Web.FormController do
  use Web, :controller

  alias App.Document.Draft
  alias App.Model.Form
  alias App.Model.Team
  alias App.Operation.TryForm
  alias Web.FormOwner

  # A form as PDFs (#950): its blank page, and a try, for an organization's form or a
  # team's own (#1083). Found through the URL's organization or team, so another's is a
  # 404, and a team's while team forms are off.

  def page(conn, %{"id" => id}) do
    {_owner, form} = form!(conn, id)

    case Form.page_bytes(form) do
      nil -> raise Web.Status.NotFound
      bytes -> send_pdf(conn, bytes, "#{form.name} page.pdf")
    end
  end

  # With `draft`, a team's form tries the team admin's draft from their AI agent (#1083),
  # unsaved, as its Change page shows it.
  def try(conn, %{"id" => id} = params) do
    {owner, form} = form!(conn, id)

    with {:ok, tried} <- tried(conn, owner, form, params["draft"]),
         {:ok, attachment} <- TryForm.call(tried, owner, params["activity"]) do
      send_pdf(conn, attachment.content, "Sample #{attachment.filename}")
    else
      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: back_path(owner, form, params["draft"]))
    end
  end

  # Back to where the try was asked for: the Change page for a draft.
  defp back_path(owner, form, nil), do: FormOwner.form_path(owner, form)
  defp back_path(owner, form, _draft), do: FormOwner.edit_path(owner, form)

  defp tried(_conn, _owner, form, nil), do: {:ok, form}

  defp tried(conn, %Team{} = team, form, _draft) do
    case Draft.get(team, conn.assigns.current_user.id, form) do
      nil -> {:error, "The draft is gone. Ask your agent to check it again."}
      draft -> {:ok, %{form | text: draft.text}}
    end
  end

  defp tried(_conn, _owner, _form, _draft), do: raise(Web.Status.NotFound)

  defp form!(conn, id) do
    owner = FormOwner.get(conn.assigns)
    {owner, Form.get(owner, id) || raise(Web.Status.NotFound)}
  end

  defp send_pdf(conn, bytes, filename) do
    send_download(conn, {:binary, bytes},
      filename: Service.StringHelpers.to_filename(filename),
      content_type: "application/pdf",
      disposition: :inline
    )
  end
end
