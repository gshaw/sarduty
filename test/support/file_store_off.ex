defmodule App.FileStoreOff do
  @moduledoc """
  Turns the file store off for one test (#1032), as production runs until storage in
  Canada exists: App.Adapter.FileStore is a scratch folder everywhere else. It changes
  the app's config, so only a test that is not async may call it.
  """

  alias App.Adapter.FileStore

  def turn_off do
    original = Application.get_env(:sarduty, FileStore, [])
    Application.put_env(:sarduty, FileStore, [])
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:sarduty, FileStore, original) end)
  end
end
