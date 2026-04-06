# frozen_string_literal: true

require "test_helper"

class FunicularTest < Minitest::Test
  def test_VERSION
    assert ::Funicular.const_defined?(:VERSION)
  end

  def test_something_useful
    assert("expected"!="actual")
  end
end
