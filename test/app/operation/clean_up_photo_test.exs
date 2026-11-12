defmodule App.Operation.CleanUpPhotoTest do
  use ExUnit.Case, async: true

  alias App.Operation.CleanUpPhoto

  # What SAR Duty warns about on Add a photo (#1031): only what it can tell for sure.
  describe "warnings/2" do
    test "1 face in a bright photo warns about nothing" do
      assert CleanUpPhoto.warnings(1, false) == []
    end

    test "more than 1 face says how many" do
      assert CleanUpPhoto.warnings(2, false) == [{:faces, 2}]
      assert CleanUpPhoto.warnings(5, false) == [{:faces, 5}]
    end

    test "no face" do
      assert CleanUpPhoto.warnings(0, false) == [:no_face]
    end

    test "a dark photo, alone or after what the faces say" do
      assert CleanUpPhoto.warnings(1, true) == [:dark]
      assert CleanUpPhoto.warnings(0, true) == [:no_face, :dark]
      assert CleanUpPhoto.warnings(3, true) == [{:faces, 3}, :dark]
    end
  end
end
