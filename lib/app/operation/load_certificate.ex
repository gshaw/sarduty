defmodule App.Operation.LoadCertificate do
  @moduledoc """
  An award's certificate (#314), fetched from D4H with the team's key each time someone
  opens it: nothing is stored here. The award comes from
  `MemberQualificationAward.find_certificate!/2`, so it is the member's and has one.
  """

  alias App.Adapter.D4H
  alias App.Model.MemberQualificationAward
  alias App.Model.Team

  # cspell:ignore webp -- the WebP image type's MIME subtype
  # Opened in the browser. Anything else downloads: a file a member attached in D4H must
  # never run as a page on SAR Duty's domain, so no HTML and no SVG.
  @inline ~w(application/pdf image/png image/jpeg image/gif image/webp)

  @doc """
  `{:ok, %{body:, content_type:, filename:, inline?:}}`, or `:error` when D4H refuses.
  """
  def call(%Team{} = team, %MemberQualificationAward{} = award) do
    case team |> D4H.build_context_from_team() |> D4H.fetch_document(award.d4h_document_id) do
      {:ok, body, content_type} ->
        type = content_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()

        {:ok,
         %{
           body: body,
           content_type: type,
           filename: filename(award.qualification.title, type),
           inline?: type in @inline
         }}

      {:error, _response} ->
        :error
    end
  end

  @doc ~s(The file's name: "Standard First Aid.pdf", from the title and the type.)
  def filename(title, content_type) do
    name =
      title
      |> String.replace(~r/[^\w\s-]/u, "")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    name = if name == "", do: "Certificate", else: name

    case MIME.extensions(content_type) do
      [ext | _] -> "#{name}.#{ext}"
      [] -> name
    end
  end
end
