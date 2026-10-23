defmodule Web.ReplyLinkController do
  use Web, :controller

  alias App.Operation.ReplyToActivity
  alias Web.ReplyLinks

  # Send reply on a reminder's reply page (#488): a plain form post, so it works before
  # the page connects in a mail app's browser. The token is the only access, as on the
  # page. Back to the page either way, which shows the reply or the error.
  def create(conn, %{"token" => token} = params) do
    path = ~p"/replies/#{token}"

    with {member, activity} <- ReplyLinks.find_reply(token),
         {:ok, answer} <- answer(params["reply"]) do
      send_reply(conn, member, activity, answer, path)
    else
      :none ->
        conn |> put_flash(:error, "Select I'll be there or Can't make it.") |> redirect(to: path)

      nil ->
        redirect(conn, to: path)
    end
  end

  defp send_reply(conn, member, activity, answer, path) do
    case ReplyToActivity.call(activity.team, activity, member, answer, nil, DateTime.utc_now()) do
      {:ok, _attendance} ->
        redirect(conn, to: path)

      {:error, text} ->
        conn |> put_flash(:error, text) |> redirect(to: path <> "?reply=#{answer}")
    end
  end

  defp answer("yes"), do: {:ok, :yes}
  defp answer("no"), do: {:ok, :no}
  defp answer(_other), do: :none
end
