defmodule App.Operation.RemovePasskeyTest do
  use App.DataCase

  import App.AccountsFixtures
  import App.PasskeyFixtures

  alias App.Accounts.UserPasskey
  alias App.Operation.RemovePasskey

  test "removes only the user's own passkey" do
    user = user_fixture()
    other = user_fixture()
    {passkey, _key} = passkey_fixture(user)
    {others, _key} = passkey_fixture(other)

    assert RemovePasskey.call(user, others.id) == :error
    assert [_one] = UserPasskey.list_for(other)

    assert {:ok, %UserPasskey{}} = RemovePasskey.call(user, passkey.id)
    assert UserPasskey.list_for(user) == []
  end
end
