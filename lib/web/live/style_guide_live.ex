defmodule Web.StyleGuideLive do
  use Web, :live_view_marketing

  import Web.WebComponents.A

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
      <.input type="checkbox" name="some_text_field" value="" label="Remember me">
        A hint under a checkbox can be very useful.
      </.input>

      <.input type="textarea" name="attendance_export" value="" label="Text area">
        Copy the attendance record from an exported CSV file in Excel and paste into this text area. <pre>It can even have formatted text</pre>
      </.input>
      <div>And this is text right after a text area</div>
      <.input type="text" name="some_text_field" value="" label="Another text field" />
    </.style_group>

    <.style_group title=".table">
      <.table
        id="attendance_records"
        rows={[
          %{name: "Alice in Wonderland", age: 19},
          %{name: "Bob", age: 42},
          %{name: "Carol", age: 33},
          %{name: "Doug", age: 69}
        ]}
      >
        <:col :let={_record} label="">
          <div class="_mb-2">
            <.input type="checkbox" name="fake" />
          </div>
        </:col>
        <:col :let={user} label="Name"><%= user.name %></:col>
        <:col :let={user} label="Age"><%= user.age %></:col>
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

  def style_group(assigns) do
    ~H"""
    <section class="shadow p-4 space-y-4 mb-8 rounded">
      <h2 class="heading font-mono"><%= @title %></h2>
      <%= render_slot(@inner_block) %>
    </section>
    """
  end
end
