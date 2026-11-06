defmodule Service.TypstTest do
  use ExUnit.Case, async: true

  # cspell:ignore Łukasz Nowak -- a name past WinAnsi (#917)

  test "the version is pinned the same in .mise.toml, the Dockerfile, and Service.Typst" do
    version = Service.Typst.version()
    assert File.read!(".mise.toml") =~ ~s(typst = "#{version}")
    assert File.read!("Dockerfile") =~ "ARG TYPST_VERSION=#{version}"
    assert Service.Typst.installed_version() == {:ok, version}
  end

  test "makes a PDF with Arimo and the images it's given" do
    png = File.read!("priv/pdf/sample-mark.png")

    assert {:ok, "%PDF-" <> _ = pdf} =
             Service.Typst.compile(
               ~s|#set text(font: "Arimo")\nŁukasz Nowak #image("mark.png")|,
               %{"mark.png" => png}
             )

    assert pdf =~ "+Arimo-Regular"
  end

  test "a warning fails the run, as an unknown font does" do
    assert {:error, warning} = Service.Typst.compile(~s|#set text(font: "Helvetica")\nHi|)
    assert warning =~ "unknown font family: helvetica"
  end

  test "an error says what Typst said" do
    assert {:error, "Typst stopped with status 1: " <> error} =
             Service.Typst.compile(~s|#image("missing.png")|)

    assert error =~ "missing.png"
  end
end
