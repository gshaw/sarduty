defmodule App.Operation.AddPasskeyTest do
  use App.DataCase

  import App.AccountsFixtures
  import App.PasskeyFixtures

  alias App.Accounts.UserPasskey
  alias App.Accounts.WebAuthn
  alias App.Operation.AddPasskey

  @safari "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) Version/26.1 Mobile Safari/605.1.15"

  test "saves a passkey and emails the account that it was added" do
    user = user_fixture(%{email: "alex.chen@example.com"})
    challenge = WebAuthn.registration_challenge()
    params = create_answer(authenticator(), challenge)

    assert {:ok, passkey} = AddPasskey.call(user, challenge, params, @safari)
    assert passkey.name == "iCloud Keychain"
    assert passkey.added_with == "iPhone, Safari"
    assert [%UserPasskey{}] = UserPasskey.list_for(user)

    assert_received {:email, %{subject: "Passkey added to your SAR Duty account"} = email}
    assert email.to == [{"", "alex.chen@example.com"}]
    assert email.text_body =~ "iCloud Keychain, added on iPhone, Safari"
  end

  test "refuses a passkey made for another challenge, and one already saved" do
    user = user_fixture()
    key = authenticator()
    challenge = WebAuthn.registration_challenge()
    other = WebAuthn.registration_challenge()

    assert AddPasskey.call(user, challenge, create_answer(key, other), @safari) ==
             {:error, :invalid}

    {:ok, _passkey} = AddPasskey.call(user, challenge, create_answer(key, challenge), @safari)
    assert AddPasskey.call(user, other, create_answer(key, other), @safari) == {:error, :taken}
    assert length(UserPasskey.list_for(user)) == 1
  end
end
