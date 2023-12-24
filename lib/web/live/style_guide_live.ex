defmodule Web.StyleGuideLive do
  use Web, :live_view_marketing_layout

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Style Guide")}
  end

  def render(assigns) do
    ~H"""
    <header class="mb-8">
      <h1 class="title">
        Style Guide
      </h1>
    </header>

    <.style_group title=".colors">
      <div class="grid grid-cols-5">
        <.color_swatch bg="bg-base-0" fg="text-base-content" />
        <.color_swatch bg="bg-base-1" fg="text-base-content" />
        <.color_swatch bg="bg-base-2" fg="text-base-content" />
        <.color_swatch bg="bg-base-3" fg="text-base-content" />
        <.color_swatch bg="bg-base-content" fg="text-base-1" />

        <.color_swatch bg="bg-primary-1" fg="text-primary-content" />
        <.color_swatch bg="bg-secondary-1" fg="text-secondary-content" />
        <.color_swatch bg="bg-success-1" fg="text-success-content" />
        <.color_swatch bg="bg-warning-1" fg="text-warning-content" />
        <.color_swatch bg="bg-danger-1" fg="text-danger-content" />

        <.color_swatch bg="bg-primary-2" fg="text-primary-content" />
        <.color_swatch bg="bg-secondary-2" fg="text-secondary-content" />
        <.color_swatch bg="bg-success-2" fg="text-success-content" />
        <.color_swatch bg="bg-warning-2" fg="text-warning-content" />
        <.color_swatch bg="bg-danger-2" fg="text-danger-content" />
      </div>
    </.style_group>

    <.style_group title=".a">
      <div class="flex space-x-4">
        <.a navigate="/styles">Default Link</.a>
        <.a kind={:custom} navigate="/styles">Unstyled</.a>
      </div>
    </.style_group>
    <.style_group title=".input">
      <.input type="text" name="some_text_field" value="" label="A text field">
        With a hint.
      </.input>
      <.input type="checkbox" name="some_checkbox_field" value="" label="Remember me">
        A hint under a checkbox can be very useful.
      </.input>

      <.input
        type="select"
        name="sel"
        value="all"
        options={["all", "some", "none"]}
        label="A select field with width auto sized"
        class="w-auto"
      >
        This is the hint for a select field.
      </.input>

      <.input type="textarea" name="attendance_export" value="" label="Text area">
        Copy the attendance record from an exported CSV file in Excel and paste into this text area. <pre>It can even have formatted text</pre>
      </.input>
      <div>And this is text right after a text area</div>
      <.input
        type="text"
        name="some_text_field"
        value=""
        label="A field with an error"
        class="md:w-1/2"
        errors={["is invalid"]}
        phx-connected={JS.remove_class("phx-no-feedback", to: ".phx-no-feedback")}
      />
    </.style_group>

    <.style_group title=".table" class="w-1/3">
      <.table
        id="attendance_records"
        rows={[
          %{name: "Alice in Wonderland looking through the looking glass", age: 9},
          %{name: "Bob", age: 42},
          %{name: "Carol", age: 33},
          %{name: "Doug", age: 104}
        ]}
      >
        <:header_row>
          <th></th>
          <th colspan="2" class="text-center">
            A header can span multiple columns
          </th>
        </:header_row>
        <:col :let={_record} label=""><.input type="checkbox" name="fake" /></:col>
        <:col :let={user} label="Name"><%= user.name %></:col>
        <:col :let={user} label="Age in years" class="text-right">
          <%= user.age %>
        </:col>
      </.table>
    </.style_group>

    <.style_group title=".btn and .form_actions">
      <.form_actions>
        <button class="btn btn-success">Save</button>
        <button class="btn btn-success">Save and Close</button>
        <button class="btn">Cancel</button>
        <button class="btn btn-link">More Information</button>
        <:trailing>
          <button class="btn btn-danger">Delete</button>
        </:trailing>
      </.form_actions>
      <p class="pt-8">
        Examples of all button styles but the app mainly uses the default, success, link, and danger.
      </p>
      <.form_actions>
        <.button disabled class="btn btn-primary">Disabled</.button>
        <button class="btn btn-primary">Primary</button>
        <button class="btn btn-secondary">Secondary</button>
        <button class="btn">Default</button>
        <button class="btn btn-link">Link</button>
      </.form_actions>
      <.form_actions>
        <button class="btn btn-success">Success</button>
        <button class="btn btn-warning">Warning</button>
        <button class="btn btn-danger">Danger</button>
      </.form_actions>
      <.form_actions>
        <button class="btn btn-lg">Large</button>
        <button class="btn">Normal</button>
        <button class="btn btn-sm">Small</button>
      </.form_actions>
      <div>
        <a class="btn btn-sm btn-outline">Log in</a>
        <a class="btn btn-sm btn-primary">Sign up for FREE</a>
      </div>
    </.style_group>
    <.style_group title=".badge">
      <div class="flex space-x-2">
        <span class="badge">Default</span>
        <span class="badge badge-primary">Primary</span>
        <span class="badge badge-secondary">Secondary</span>
        <span class="badge badge-success">Success</span>
        <span class="badge badge-warning">Warning</span>
        <span class="badge badge-danger">Danger</span>
      </div>
    </.style_group>
    <.style_group title=".typography">
      <h1 class="title-hero">This is a .title-hero</h1>
      <h1 class="title">This is a .title</h1>
      <p class="lead">This is .lead text inside a <code>p</code> tag.</p>
      <p>This is another paragraph of text.</p>
      <h2 class="heading">This is a .heading element</h2>
      <p>This is a paragraph of text. Paragraphs have a bottom margin.</p>

      <h3 class="subheading">This is a .subheading element</h3>
      <div class="paragraph">
        This is a paragraph of text inside a <code>div</code> block with styled with .paragraph.
      </div>
    </.style_group>
    """
  end

  attr :class, :string, default: nil
  attr :title, :string, required: true
  slot :inner_block, required: true

  def style_group(assigns) do
    ~H"""
    <section class={["shadow p-4 space-y-4 mb-8 rounded", @class]}>
      <h2 class="heading font-mono"><%= @title %></h2>
      <%= render_slot(@inner_block) %>
    </section>
    """
  end

  attr :fg, :string, required: true
  attr :bg, :string, required: true

  def color_swatch(assigns) do
    ~H"""
    <div class={[
      "px-8 py-6 m-2 text-center inline-block align-middle rounded text-xs",
      @bg,
      @fg
    ]}>
      <%= @bg %>
    </div>
    """
  end
end
