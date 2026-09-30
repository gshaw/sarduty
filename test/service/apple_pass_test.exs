defmodule Service.ApplePassTest do
  use ExUnit.Case, async: true

  alias App.ApplePassCredentials

  test "packs the files with a manifest of their hashes and a signature over it" do
    credentials = ApplePassCredentials.generate()
    files = %{"pass.json" => ~s({"formatVersion":1}), "icon.png" => "not really a png"}

    {:ok, entries} = files |> Service.ApplePass.package(credentials) |> :zip.extract([:memory])
    unpacked = Map.new(entries, fn {name, data} -> {to_string(name), data} end)

    assert unpacked |> Map.keys() |> Enum.sort() ==
             ["icon.png", "manifest.json", "pass.json", "signature"]

    manifest = Jason.decode!(unpacked["manifest.json"])

    for {name, data} <- files do
      assert manifest[name] == :sha |> :crypto.hash(data) |> Base.encode16(case: :lower)
    end

    assert verify(unpacked["signature"], unpacked["manifest.json"], credentials.certificate)
  end

  # cspell:ignore noverify -- an openssl flag: skip checking the test certificate's chain
  defp verify(signature, manifest, certificate) do
    dir = Path.join(System.tmp_dir!(), "apple-pass-verify-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      for {name, data} <- [signature: signature, manifest: manifest, cert: certificate],
          do: dir |> Path.join("#{name}") |> File.write!(data)

      {_output, status} =
        System.cmd(
          "openssl",
          ~w(smime -verify -binary -inform DER -noverify -in #{dir}/signature -content #{dir}/manifest -signer #{dir}/signer),
          stderr_to_stdout: true,
          env: Service.ApplePass.without_environment()
        )

      status == 0 and dir |> Path.join("signer") |> File.read!() =~ "BEGIN CERTIFICATE"
    after
      File.rm_rf!(dir)
    end
  end
end
