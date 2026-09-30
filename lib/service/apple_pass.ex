defmodule Service.ApplePass do
  @moduledoc """
  Packs the files of an Apple Wallet pass into a signed `.pkpass`: a zip with a
  `manifest.json` of SHA-1 hashes and a detached PKCS #7 `signature` over the manifest,
  made with the pass type certificate and Apple's WWDR G4 intermediate.
  """

  @doc """
  `files` maps each file name in the pass to its contents: `pass.json` and the PNGs.
  `credentials` has the PEM `:certificate` and `:private_key`.
  """
  def package(files, credentials) do
    manifest =
      files
      |> Map.new(fn {name, data} -> {name, sha1(data)} end)
      |> Jason.encode!()

    signature = sign(manifest, credentials)

    entries =
      files
      |> Map.merge(%{"manifest.json" => manifest, "signature" => signature})
      |> Enum.map(fn {name, data} -> {String.to_charlist(name), data} end)

    {:ok, {_name, zip}} = :zip.create(~c"pass.pkpass", entries, [:memory])
    zip
  end

  def wwdr_certificate_path, do: Application.app_dir(:sarduty, "priv/apple/wwdr_g4.pem")

  defp sha1(data), do: :sha |> :crypto.hash(data) |> Base.encode16(case: :lower)

  @doc "Clears every environment variable but PATH, so openssl sees none of the app's secrets."
  def without_environment do
    for {name, _value} <- System.get_env(), name != "PATH", do: {name, nil}
  end

  # cspell:ignore inkey -- an openssl flag
  # Erlang has no PKCS #7 signing, so this uses the openssl CLI, which the Fly image
  # installs.
  defp sign(manifest, %{certificate: certificate, private_key: private_key}) do
    paths =
      for name <- [:manifest, :certificate, :key], into: %{}, do: {name, Service.Temp.path()}

    try do
      File.write!(paths.manifest, manifest)
      File.write!(paths.certificate, certificate)
      File.touch!(paths.key)
      File.chmod!(paths.key, 0o600)
      File.write!(paths.key, private_key)

      {signature, 0} =
        System.cmd(
          "openssl",
          [
            "smime",
            "-binary",
            "-sign",
            "-certfile",
            wwdr_certificate_path(),
            "-signer",
            paths.certificate,
            "-inkey",
            paths.key,
            "-in",
            paths.manifest,
            "-outform",
            "DER"
          ],
          env: without_environment()
        )

      signature
    after
      paths |> Map.values() |> Enum.each(&File.rm/1)
    end
  end
end
