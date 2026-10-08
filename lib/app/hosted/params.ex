defmodule App.Hosted.Params do
  @moduledoc """
  A D4H request body, in D4H's camelCase field names, as attrs for the hosted
  schemas. Only fields a body names are returned, so a PATCH changes only those. A time
  that won't parse is passed on as given, and the changeset rejects it.
  """

  def to_attrs("members", body) do
    body
    |> pick(%{
      "name" => :name,
      "ref" => :ref,
      "position" => :position,
      "email" => :email,
      "deprecatedAddress" => :address,
      "status" => :status,
      "startsAt" => {:starts_at, &time/1},
      # Not in D4H's API, which sets access levels in its web app only.
      "permission" => {:permission, &permission/1}
    })
    |> put_phone(body)
  end

  def to_attrs(resource, body) when resource in ["events", "exercises", "incidents"] do
    body
    |> pick(%{
      "reference" => :reference,
      "referenceDescription" => :title,
      "description" => :description,
      "trackingNumber" => :tracking_number,
      "startsAt" => {:starts_at, &time/1},
      "endsAt" => {:ends_at, &time/1}
    })
    |> put_address(body)
    |> put_location(body)
  end

  def to_attrs("attendance", body) do
    pick(body, %{
      "activityId" => :activity_id,
      "memberId" => :member_id,
      "status" => :status,
      "startsAt" => {:starts_at, &time/1},
      "endsAt" => {:ends_at, &time/1}
    })
  end

  def to_attrs("member-qualifications", body) do
    pick(body, %{
      "title" => :title,
      "description" => :description,
      "expiresMonthsDefault" => :expires_months_default
    })
  end

  def to_attrs("member-qualification-awards", body) do
    pick(body, %{
      "memberId" => :member_id,
      "qualificationId" => :qualification_id,
      "startsAt" => {:starts_at, &time/1},
      "endsAt" => {:ends_at, &time/1}
    })
  end

  def to_attrs("member-group-memberships", body),
    do: pick(body, %{"groupId" => :group_id, "memberId" => :member_id})

  def to_attrs(resource, body) when resource in ["member-groups", "tags"],
    do: pick(body, %{"title" => :title})

  defp pick(body, fields) do
    for {name, field} <- fields, Map.has_key?(body, name), into: %{} do
      case field do
        {key, convert} -> {key, convert.(body[name])}
        key -> {key, body[name]}
      end
    end
  end

  # D4H takes `phone: {mobile: …}` and returns `mobile: {phone: …}`.
  defp put_phone(attrs, %{"phone" => %{"mobile" => mobile}}), do: Map.put(attrs, :phone, mobile)
  defp put_phone(attrs, _body), do: attrs

  defp put_address(attrs, %{"address" => address}) when is_map(address) do
    address
    |> pick(%{"street" => :street, "town" => :town, "region" => :region, "country" => :country})
    |> Map.merge(attrs)
  end

  defp put_address(attrs, _body), do: attrs

  defp put_location(attrs, %{"location" => %{"latitude" => lat, "longitude" => lng}}),
    do: Map.merge(attrs, %{lat: lat, lng: lng})

  defp put_location(attrs, %{"location" => nil}), do: Map.merge(attrs, %{lat: nil, lng: nil})
  defp put_location(attrs, _body), do: attrs

  defp time(nil), do: nil

  defp time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> DateTime.truncate(time, :second)
      {:error, _reason} -> value
    end
  end

  defp time(value), do: value

  @permissions %{"OWNER" => 0, "EDITOR" => 1, "MEMBER" => 2, "MEMBER_PLUS" => 3, "NO_ACCESS" => 4}

  defp permission(name) when is_binary(name), do: Map.get(@permissions, name, name)
  defp permission(value), do: value
end
