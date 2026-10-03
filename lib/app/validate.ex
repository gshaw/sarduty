defmodule App.Validate do
  alias App.Validate

  defdelegate address(changeset, field), to: Validate.Address, as: :call
  defdelegate email(changeset, field), to: Validate.Email, as: :call
  defdelegate name(changeset, field), to: Validate.Name, as: :call

  # defdelegate password_strength(changeset, field), to: Validate.PasswordStrength, as: :call
  # defdelegate password_correct(changeset, field, user), to: Validate.PasswordCorrect, as: :call

  # defdelegate two_factor_auth_code(changeset, field, encoded_totp_secret),
  #   to: Validate.TwoFactorAuthCode,
  #   as: :call

  # defdelegate user_name(changeset, field), to: Validate.UserName, as: :call
end
