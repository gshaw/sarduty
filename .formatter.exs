[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  # <.a> is inline, as <a> is, so the formatter never puts a link's text on its own lines;
  # that would underline a space after it. "link" and "button" are the defaults.
  inline_matcher: ["link", "button", ~r/^\.a$/],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
