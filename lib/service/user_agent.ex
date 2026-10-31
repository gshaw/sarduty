defmodule Service.UserAgent do
  @moduledoc """
  A browser's user agent in a few words, such as "iPhone, Safari", for an email that says
  what someone wrote it on (#780). A guess from the usual names: nil when nothing fits.
  """

  # Order matters: iPhone browsers name Safari too, and Chrome and Edge name each other.
  @devices [
             {"iPad", "iPad"},
             {"iPhone", "iPhone"},
             {"Android", "Android"},
             {"CrOS", "Chromebook"}
           ] ++
             [{"Macintosh", "Mac"}, {"Windows", "Windows"}, {"Linux", "Linux"}]
  @browsers [{"Edg", "Edge"}, {"CriOS", "Chrome"}, {"FxiOS", "Firefox"}, {"Firefox/", "Firefox"}] ++
              [{"Chrome/", "Chrome"}, {"Safari/", "Safari"}]

  @doc ~s(Pure. "iPhone, Safari", "Mac", "Chrome", or nil.)
  def describe(nil), do: nil

  def describe(user_agent) when is_binary(user_agent) do
    case Enum.reject([find(@devices, user_agent), find(@browsers, user_agent)], &is_nil/1) do
      [] -> nil
      words -> Enum.join(words, ", ")
    end
  end

  defp find(names, user_agent) do
    Enum.find_value(names, fn {needle, name} -> if user_agent =~ needle, do: name end)
  end
end
