defmodule Web.DesignSystemTest do
  @moduledoc """
  Class lists use only the design system's names: the 8 spacing steps and the colour
  tokens in assets/css/theme.css. Tailwind builds nothing for any other spacing number or
  colour, so a class like mt-5 or text-zinc-600 would fail quietly in the browser. This
  test makes it fail here instead.
  """
  use ExUnit.Case, async: true

  # cspell:ignore trblxyse trblxy

  @root "../.." |> Path.expand(__DIR__)
  @theme @root |> Path.join("assets/css/theme.css") |> File.read!()

  @steps ~r/--spacing-(\d+):/
         |> Regex.scan(@theme, capture: :all_but_first)
         |> List.flatten()
         |> MapSet.new()

  @colours ~r/--color-([a-z0-9-]+):/
           |> Regex.scan(@theme, capture: :all_but_first)
           |> List.flatten()
           |> MapSet.new()

  @spacing ~r/^-?(?:m[trblxyse]?|p[trblxyse]?|gap(?:-[xy])?|space-[xy]|inset(?:-[xy])?|top|left|right|bottom|w|h|size|min-w|max-w|min-h|max-h|translate-[xy]|scroll-[mp][trblxy]?|basis)-([0-9.]+)$/
  @colour ~r/^(?:text|bg|border(?:-[trblxy])?|divide|ring|fill|stroke|outline|decoration|accent|caret|placeholder|from|via|to)-([a-z][a-z0-9-]*)$/

  # Same prefixes, not colours: sizes, alignment, widths, and styles.
  @not_colours ~w(xs sm base lg xl 2xl 3xl 4xl 5xl 7xl left right center justify start end
                  wrap nowrap balance pretty ellipsis clip inherit current transparent none
                  solid dashed dotted double hidden collapse separate cover contain fixed
                  local scroll no-repeat repeat auto top bottom underline offset t b l r x y)

  test "spacing classes use only the 8 steps" do
    for {file, class} <- classes(),
        [_, value] <- [Regex.run(@spacing, utility(class))],
        value not in ["0", "px"] do
      assert value in @steps,
             "#{file}: #{class} is off the spacing scale (#{steps()})"
    end
  end

  test "colour classes use only the tokens" do
    for {file, class} <- classes(),
        [_, value] <- [Regex.run(@colour, utility(class))],
        value not in @not_colours,
        not String.match?(value, ~r/^\d/) do
      assert value in @colours, "#{file}: #{class} is not a colour token"
    end
  end

  test "class lists have no arbitrary values" do
    for {file, class} <- classes() do
      refute class =~ ~r/-\[|-\(--|^\[/, "#{file}: #{class} is an arbitrary value"
    end
  end

  defp steps, do: @steps |> Enum.map(&String.to_integer/1) |> Enum.sort() |> Enum.join(", ")

  # Every class in a class="…" attribute or a class={…} list, with its file.
  defp classes do
    for file <- @root |> Path.join("lib/web/**/*.{ex,heex}") |> Path.wildcard(),
        source = File.read!(file),
        list <- class_strings(source),
        class <- String.split(list),
        not String.contains?(class, ["{", "}", "#", "@"]),
        do: {Path.relative_to(file, @root), class}
  end

  defp class_strings(source) do
    attrs = Regex.scan(~r/\b[a-z_]*class="([^"]*)"/, source, capture: :all_but_first)

    lists =
      for [list] <- Regex.scan(~r/\b[a-z_]*class=\{([^}]*)\}/, source, capture: :all_but_first),
          [string] <- Regex.scan(~r/"([^"]*)"/, list, capture: :all_but_first),
          do: [string]

    List.flatten(attrs ++ lists)
  end

  # The utility without its variants: md:mt-4 is mt-4.
  defp utility(class), do: class |> String.split(":") |> List.last()
end
