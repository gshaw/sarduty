defmodule Service.UserAgentTest do
  use ExUnit.Case, async: true

  alias Service.UserAgent

  # cspell:ignore KHTML -- the engine every browser's user agent names, from Konqueror

  test "names the device and the browser" do
    assert UserAgent.describe(
             "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
           ) == "iPhone, Safari"

    assert UserAgent.describe(
             "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0 Mobile/15E148 Safari/604.1"
           ) == "iPhone, Chrome"

    assert UserAgent.describe(
             "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
           ) == "Mac, Chrome"

    assert UserAgent.describe(
             "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 Edg/130.0"
           ) == "Windows, Edge"

    assert UserAgent.describe(
             "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36"
           ) == "Android, Chrome"
  end

  test "nil when it says nothing it knows" do
    assert UserAgent.describe(nil) == nil
    assert UserAgent.describe("curl/8.0") == nil
  end
end
