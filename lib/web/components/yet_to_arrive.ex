defmodule Web.Components.YetToArrive do
  @moduledoc """
  The members who signed up for an activity and have not arrived, with Call and Text
  buttons, and a line counting arrivals. Used at the door and on the team admin's Take
  attendance page (#245).
  """
  use Phoenix.Component

  import Web.Components.Core, only: [button: 1]

  attr :id, :string, default: "yet-to-arrive"
  attr :yet_to_arrive, :map, required: true, doc: "from App.Operation.BuildYetToArrive"
  attr :class, :any, default: nil

  def yet_to_arrive_list(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <p :if={@yet_to_arrive.yet_to_arrive == []} id={"#{@id}-none"}>
        Everyone who signed up has arrived.
      </p>
      <ul :if={@yet_to_arrive.yet_to_arrive != []} id={"#{@id}-members"}>
        <li
          :for={member <- @yet_to_arrive.yet_to_arrive}
          id={"#{@id}-member-#{member.id}"}
          class="flex flex-wrap items-center justify-between gap-2 py-2 border-b border-border-subtle"
        >
          <span>
            <span class="font-semibold">{member.name}</span>
            <span :if={phone(member)} class="block hint">{Service.Phone.format(phone(member))}</span>
            <span :if={!phone(member)} class="block hint">No mobile number in D4H</span>
          </span>
          <span :if={phone(member)} class="flex gap-2">
            <.button id={"#{@id}-call-#{member.id}"} href={"tel:#{phone(member)}"}>
              Call
            </.button>
            <%!-- Phoenix's link allows tel: but not sms:, so the scheme goes as a tuple. --%>
            <.button id={"#{@id}-text-#{member.id}"} href={{:sms, phone(member)}}>
              Text
            </.button>
          </span>
        </li>
      </ul>
      <p id={"#{@id}-count"} class="mt-2 hint">{arrived_text(@yet_to_arrive)}</p>
    </div>
    """
  end

  @doc "The yet to arrive count, like 4 of 11 signed up."
  def count_text(%{yet_to_arrive: members, signed_up: signed_up}),
    do: "#{length(members)} of #{signed_up} signed up"

  defp arrived_text(%{arrived: arrived, walk_ins: 0}),
    do: Service.Format.count(arrived, one: "%d member arrived.", many: "%d members arrived.")

  defp arrived_text(%{arrived: arrived, walk_ins: walk_ins}) do
    Service.Format.count(arrived, one: "%d member arrived", many: "%d members arrived") <>
      ", including #{walk_ins} who did not sign up."
  end

  # E.164 when D4H's number reads as one, so tel: and sms: links dial it.
  defp phone(%{phone: phone}), do: Service.Phone.normalize(phone) || blank_to_nil(phone)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))
end
