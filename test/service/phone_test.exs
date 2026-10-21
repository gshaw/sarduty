defmodule Service.PhoneTest do
  use ExUnit.Case, async: true

  alias Service.Phone

  test "reads North American numbers however they're typed" do
    for text <- [
          "604-555-1234",
          "(604) 555-1234",
          "604.555.1234",
          "1 604 555 1234",
          "+1 604 555 1234"
        ] do
      assert Phone.normalize(text) == "+16045551234"
    end
  end

  test "drops an extension" do
    assert Phone.normalize("604-555-1234 x12") == "+16045551234"
    assert Phone.normalize("604-555-1234 ext. 12") == "+16045551234"
  end

  test "keeps another country's code when it starts with +" do
    assert Phone.normalize("+44 20 7946 0958") == "+442079460958"
  end

  test "nil for what isn't a number" do
    for text <- [nil, "", "555-1234", "call me", "+12"] do
      assert Phone.normalize(text) == nil
    end
  end

  test "formats a number to read, and keeps anything else as written" do
    assert Phone.format("+16045551234") == "604-555-1234"
    assert Phone.format("(604) 555 1234") == "604-555-1234"
    assert Phone.format("+44 20 7946 0958") == "+442079460958"
    assert Phone.format(" ask the office ") == "ask the office"
    assert Phone.format("  ") == nil
    assert Phone.format(nil) == nil
  end
end
