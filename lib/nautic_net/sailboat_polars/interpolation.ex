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
    spline_model = BezierSpline.fit(theta, r)

    # use the tail-end of the spline prediction as part of our linear model
    dt = 5 * pi() / 180

    # Fit {0, 0} and {cutoff_theta, dy} as points for the linear "extrapolation"
    lower_linear_model =
      Scholar.Interpolation.Linear.fit(
        Nx.stack([0, theta[0], theta[1]]),
        Nx.stack([0, r[0], r[1]])
      )

    upper_linear_model = Scholar.Interpolation.Linear.fit(theta[-2..-1], r[-2..-1])

    low_cutoff_theta = Nx.new_axis(theta[0], 0)
    top_cutoff_theta = Nx.new_axis(theta[-1], 0)

    {lower_linear_model, upper_linear_model, spline_model, low_cutoff_theta, top_cutoff_theta}
  end

  defn predict(
         {lower_linear_model, upper_linear_model, spline_model, low_cutoff_theta,
          top_cutoff_theta},
         theta
       ) do
    # wrap the phase
    theta = theta * pi() / 180
    theta = Nx.remainder(Nx.remainder(theta, 2 * pi()) + 2 * pi(), 2 * pi())
    # treat negative values as their symmetrical for prediction
    # because the interpolation is only valid for [0, pi]
    theta = Nx.select(theta > pi(), 2 * pi() - theta, theta)

    low_linear_pred = Scholar.Interpolation.Linear.predict(lower_linear_model, theta)
    top_linear_pred = Scholar.Interpolation.Linear.predict(upper_linear_model, theta)
    spline_pred = BezierSpline.predict(spline_model, theta)

    low_continuation = Nx.select(theta <= low_cutoff_theta, low_linear_pred, spline_pred)
    Nx.select(theta >= top_cutoff_theta, top_linear_pred, low_continuation)
  end

  def predict_new_tws(models_by_tws, target_tws, theta) do
    [first | _] = tws_keys = models_by_tws |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    if target_tws <= first do
      # we're between 0 and the first interval
      stop_speeds = predict(models_by_tws[first], theta)

      t = target_tws / first

      Nx.multiply(stop_speeds, t)
    else
      {start_tws, stop_tws} =
        tws_keys
        |> Enum.zip_with(tl(tws_keys), fn start, stop ->
          {target_tws in start..stop, {start, stop}}
        end)
        |> Keyword.fetch!(true)

      start_speeds = predict(models_by_tws[start_tws], theta)
      stop_speeds = predict(models_by_tws[stop_tws], theta)

      t = (target_tws - start_tws) / (stop_tws - start_tws)

      lerp(start_speeds, stop_speeds, t)
    end
  end

  defnp lerp(start, stop, t) do
    start + (stop - start) * t
  end
end
