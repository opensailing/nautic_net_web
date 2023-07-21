defmodule NauticNet.MathTest do
  use ExUnit.Case

  alias NauticNet.Math

  @delta 0.001

  describe "add_degress/2" do
    test "works" do
      assert_in_delta Math.add_degrees(0, 0), 0, @delta
      assert_in_delta Math.add_degrees(0, 10), 10, @delta
      assert_in_delta Math.add_degrees(0, 200), 200, @delta
      assert_in_delta Math.add_degrees(0, 360), 0, @delta
      assert_in_delta Math.add_degrees(0, 370), 10, @delta
      assert_in_delta Math.add_degrees(0, -10), 350, @delta
      assert_in_delta Math.add_degrees(20, -40), 340, @delta
      assert_in_delta Math.add_degrees(-10, -10), 340, @delta
      assert_in_delta Math.add_degrees(350, 350), 340, @delta
    end
  end

  describe "deg2rad/1" do
    test "works" do
      assert Math.deg2rad(0) == 0
      assert Math.deg2rad(90) == 0.5 * :math.pi()
      assert Math.deg2rad(180) == 1.0 * :math.pi()
      assert Math.deg2rad(270) == 1.5 * :math.pi()
      assert Math.deg2rad(360) == 2.0 * :math.pi()
    end
  end

  describe "rad2deg/1" do
    test "works" do
      assert Math.rad2deg(0) == 0
      assert Math.rad2deg(0.5 * :math.pi()) == 90
      assert Math.rad2deg(1.0 * :math.pi()) == 180
      assert Math.rad2deg(1.5 * :math.pi()) == 270
      assert Math.rad2deg(2.0 * :math.pi()) == 360
    end
  end
end
