defmodule Web.Components.ChoiceSwitch do
  @moduledoc """
  A switch with two to four named choices, one always on: the switch's track and blue
  knob, with no save button. A tap slides the knob and the form around it saves, and a
  toast says so. Radio buttons underneath, so arrow keys move between choices, and CSS
  alone moves the knob, so a LiveView patch can't leave it behind. See /styles/forms.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [icon: 1]

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true, doc: "what it sets, for screen readers: Theme"
  attr :value, :string, default: nil, doc: "the choice that's on"

  attr :options, :list,
    required: true,
    doc: "two to four `{value, label}` or `{value, label, icon}`"

  attr :class, :any, default: nil

  def choice_switch(assigns) do
    ~H"""
    <div id={@id} class={["choice-switch", @class]} role="radiogroup" aria-label={@label}>
      <label :for={option <- @options}>
        <input
          type="radio"
          id={"#{@id}-#{elem(option, 0)}"}
          name={@name}
          value={elem(option, 0)}
          checked={elem(option, 0) == @value}
        />
        <.icon :if={tuple_size(option) == 3} name={elem(option, 2)} size={:sm} />
        {elem(option, 1)}
      </label>
    </div>
    """
  end
end
