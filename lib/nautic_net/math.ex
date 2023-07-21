defmodule NauticNet.Math do
  @moduledoc """
  Simple arithmetic.
  """

  @pi :math.pi()
  @two_pi 2 * :math.pi()

  @doc """
  Adds two headings together in radians, wrapping around at 0.
  """
  def add_radians(rad1, rad2) do
    :math.fmod(rad1 + rad2 + @two_pi, @two_pi)
  end

  @doc """
  Adds two headings together in degrees, wrapping around at 0°.
  """
  def add_degrees(deg1, deg2) do
    rad2deg(add_radians(deg2rad(deg1), deg2rad(deg2)))
  end

  @doc """
  Converts degrees to radians.
  """
  def deg2rad(deg), do: deg * @pi / 180

  @doc """
  Converts radians to degrees.
  """
  def rad2deg(rad), do: rad * 180 / @pi
end
