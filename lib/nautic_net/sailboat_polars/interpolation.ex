defmodule NauticNet.SailboatPolars.Interpolation do
  @moduledoc """
  Interpolation for polar data.

  Angles are wrapped to [-pi, pi] for fit and prediction
  """

  import Nx.Defn
  import Nx.Constants

  alias Scholar.Interpolation.BezierSpline

  defn fit(theta, r) do
    # sort inputs based on theta
    idx = Nx.argsort(theta)
    theta = Nx.take_along_axis(theta, idx) * pi() / 180
    r = Nx.take_along_axis(r, idx)

    # this assumes theta's domain is [0deg, 180deg]
    BezierSpline.fit(theta, r)
  end

  defn predict(model, theta) do
    # wrap the phase
    theta = theta * pi() / 180
    theta = Nx.remainder(Nx.remainder(theta, 2 * pi()) + 2 * pi(), 2 * pi())
    # treat negative values as their symmetrical for prediction
    # because the interpolation is only valid for [0, pi]
    theta = Nx.select(theta > pi(), 2 * pi() - theta, theta)

    BezierSpline.predict(model, theta)
  end
end
