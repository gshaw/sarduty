defmodule App.FileStoreOff do
  @moduledoc """
  Changes the file store for one test: App.Adapter.FileStore is a scratch folder
  otherwise. `turn_off/0` leaves no store; `use_s3/0` sends S3 calls to
  `Req.Test.stub(App.Adapter.FileStore, …)`. Both change the app's config, so only a
  test that is not async may call them.
  """

  alias App.Adapter.FileStore

  def turn_off, do: put([])

  def use_s3,
    do:
      put(
        bucket: "sarduty-files-test",
        region: "ca-west-1",
        access_key_id: "test-key-id",
        secret_access_key: "test-secret",
        plug: {Req.Test, FileStore}
      )

  defp put(config) do
    original = Application.get_env(:sarduty, FileStore, [])
    Application.put_env(:sarduty, FileStore, config)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:sarduty, FileStore, original) end)
  end
end
