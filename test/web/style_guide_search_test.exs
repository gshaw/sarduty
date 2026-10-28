defmodule Web.StyleGuideSearchTest do
  use ExUnit.Case, async: true

  alias Web.StyleGuideHTML
  alias Web.StyleGuideSearch

  setup_all do
    %{index: StyleGuideSearch.build()}
  end

  defp pages do
    for {_group, _title, _about, pages} <- StyleGuideHTML.groups(),
        {page, _title, _about} <- pages,
        do: page
  end

  defp hits(query, index), do: for(group <- StyleGuideSearch.run(query, index), do: group.hits)

  test "every template in pages/ is a page in groups/0, so search finds it" do
    # group.html.heex lists a group's pages, from groups/0's own words.
    templates =
      for path <- Path.wildcard("lib/web/controllers/style_guide_html/pages/*.html.heex"),
          name = Path.basename(path, ".html.heex"),
          name != "group",
          do: String.to_existing_atom(name)

    assert Enum.sort(templates) == Enum.sort(pages())
  end

  test "every page has an entry with its text", %{index: index} do
    for page <- pages() do
      [lead | _sections] = Enum.filter(index, &(&1.page == page))
      assert lead.heading == nil
      assert lead.path == StyleGuideHTML.page_path(page)
      assert Enum.any?(index, &(&1.page == page and &1.text != "")), "#{page} has no text"
    end
  end

  test "words on a page find it", %{index: index} do
    assert [[%{title: "Phone › In the app"} = tel | _rest]] = hits("tel:", index)
    assert tel.path == "/styles/phone#:~:text=In%20the%20app"
    assert tel.snippet =~ "tel:"

    assert [%{title: "Confirm dialog › How it works"} | _rest] =
             "cancel" |> hits(index) |> List.flatten()
  end

  test "a match in a page title ranks above one in a heading, then in the text", %{
    index: index
  } do
    assert [%{kind: :page, title: "Phone"} | _rest] = "phone" |> hits(index) |> List.flatten()

    entries = [
      entry(:writing, "Writing", nil, "Buttons say what they do."),
      entry(:button, "Button", nil, "Kinds and sizes."),
      entry(:forms, "Forms", "Buttons in a form", "Save goes last.")
    ]

    assert [%{hits: hits}] = StyleGuideSearch.run("button", entries)
    assert Enum.map(hits, & &1.title) == ["Button", "Forms › Buttons in a form", "Writing"]
  end

  test "a section found only by its page's title is left to the page" do
    entries = [entry(:phone, "Phone", nil, ""), entry(:phone, "Phone", "When to use", "Any.")]
    assert [%{hits: [%{kind: :page}]}] = StyleGuideSearch.run("phone", entries)
  end

  test "words match where a word starts, all of them, in any order" do
    entries = [entry(:tag, "Tag", nil, "A word or two of status, such as Not published.")]

    assert [_group] = StyleGuideSearch.run("published not", entries)
    assert [] = StyleGuideSearch.run("shed", entries)
    assert [] = StyleGuideSearch.run("published draft", entries)
  end

  test "a page splits at its headings, but not at an example's" do
    html = """
    <nav class="side-nav"><a>When to use</a></nav>
    <main class="guide-main">
      <ol class="breadcrumbs"><li>Style guide</li></ol>
      <h1>Card</h1>
      <p class="lead">A box for <code>one</code> topic.</p>
      <div class="demo"><h2>Team records</h2><p>12 incidents</p></div>
      <h2>When to use</h2>
      <p>Tiles in a grid.</p>
      <h3>When not to use</h3>
      <p>A sidebar.</p>
    </main>
    """

    page = %{page: :card, title: "Card", about: "A box."}

    assert [lead, use, not_use] = StyleGuideSearch.sections(html, page)
    assert lead.text == "Card A box for one topic. Team records 12 incidents"
    assert %{heading: "When to use", text: "Tiles in a grid.", id: "card--when-to-use"} = use
    # The side nav says "When to use" first, so the words after the heading pick it.
    assert use.path == "/styles/card#:~:text=When%20to%20use,-Tiles%20in%20a"
    assert not_use.path == "/styles/card#:~:text=When%20not%20to%20use"
  end

  test "recent picks come back from their keys, newest first", %{index: index} do
    assert [%{kind: :recent, hits: [phone, button]}] =
             StyleGuideSearch.recent(
               ["section:phone--in-the-app", "page:gone", "page:button", 12],
               index
             )

    assert phone.title == "Phone › In the app"
    assert button.path == "/styles/button"
    assert StyleGuideSearch.recent(["page:gone"], index) == []
  end

  defp entry(page, title, heading, text) do
    %{
      id: "#{page}--#{heading}",
      page: page,
      title: title,
      about: "About #{title}.",
      heading: heading,
      text: text,
      path: StyleGuideHTML.page_path(page),
      group: :components,
      group_title: "Components"
    }
  end
end
