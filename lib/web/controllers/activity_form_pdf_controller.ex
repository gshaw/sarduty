defmodule Web.ActivityFormPDFController do
  use Web, :controller

  alias App.Model.Activity
  alias App.Model.Form
  alias App.Operation.CreateFormPDF

  # Download draft PDF on an activity's form page (#950): the page's form posts its
  # answers here, since a LiveView can't send a PDF. Each one is saved as it was made.
  # Team admins only; the form is found on for the team's organization.
  def create(conn, %{"id" => id, "form_id" => form_id} = params) do
    %{current_team: team, current_user: user} = conn.assigns
    activity = Activity.find!(team, id)
    form = Form.get_enabled(team, form_id) || raise(Web.Status.NotFound)

    case CreateFormPDF.call(team, form, activity, user, typed(params), DateTime.utc_now()) do
      {:ok, attachment} ->
        send_download(conn, {:binary, attachment.content},
          filename: attachment.filename,
          content_type: attachment.content_type,
          disposition: :inline
        )

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/teams/#{team}/activities/#{activity.id}/forms/#{form.id}")
    end
  end

  defp typed(%{"answers" => %{} = answers}), do: answers
  defp typed(_params), do: %{}
end
