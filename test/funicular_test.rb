# frozen_string_literal: true

require "test_helper"

class FunicularTest < Test::Unit::TestCase
  test "VERSION" do
    assert do
      ::Funicular.const_defined?(:VERSION)
    end
  end

  test "something useful" do
    assert_not_equal("expected", "actual")
  end
end
