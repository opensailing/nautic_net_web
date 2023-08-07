defmodule NauticNetWeb.SailboatPolarsLive.PolarPlot do
  alias VegaLite, as: Vl

  def plot_grid(opts \\ []) do
    opts =
      Keyword.validate!(opts, [
        :height,
        :width,
        :color,
        :radius_marks,
        :title,
        angle_marks: [0, 90, 180, 270],
        theta_offset: 0,
        opacity: 0.5,
        stroke_color: "white",
        stroke_opacity: 1
      ])

    width = height = max(opts[:height], opts[:width])

    grid_layers = angle_layers(opts)
    radius_layers = radius_layers(opts)

    Vl.new(
      height: height,
      width: width,
      title: [text: opts[:title], align: "center", anchor: "middle", font_size: 25]
    )
    |> Vl.data_from_values(%{_r: [1]})
    |> Vl.layers(grid_layers ++ radius_layers)
  end

  defp rad(angle), do: angle * :math.pi() / 180

  defp angle_layers(opts) do
    angle_marks_input = opts[:angle_marks]
    theta_offset = opts[:theta_offset]

    angle_marks = [0 | Enum.sort(angle_marks_input)] |> Enum.map(fn x -> x + theta_offset end)
    angle_marks2 = tl(angle_marks) ++ [360 + theta_offset]

    [angle_marks, angle_marks2]
    |> Enum.zip_with(fn [t, t2] ->
      label =
        if t != 0 or (t == 0 and 0 in angle_marks_input) do
          Vl.new()
          |> Vl.mark(:text,
            text: to_string(t - theta_offset) <> "º",
            theta: "#{rad(t)}",
            radius: [expr: "min(width, height) * 0.55"]
          )
        else
          []
        end

      [
        Vl.new()
        |> Vl.mark(:arc,
          theta: "#{rad(t)}",
          theta2: "#{rad(t2)}",
          stroke: opts[:stroke_color],
          stroke_opacity: opts[:stroke_opacity],
          opacity: opts[:opacity],
          color: opts[:color]
        ),
        label
      ]
    end)
    |> List.flatten()
  end

  defp radius_layers(opts) do
    radius_marks = opts[:radius_marks]

    max_radius = Enum.max(radius_marks)

    {theta, theta2} = Enum.min_max(opts[:angle_marks])

    radius_marks_vl =
      Enum.map(radius_marks, fn r ->
        Vl.mark(Vl.new(), :arc,
          radius: [expr: "#{r / max_radius} * min(width, height)/2"],
          radius2: [expr: "#{r / max_radius} * min(width, height)/2 + 1"],
          theta: theta |> rad() |> to_string(),
          theta2: theta2 |> rad() |> to_string(),
          color: opts[:stroke_color],
          opacity: opts[:stroke_opacity]
        )
      end)

    radius_ruler_vl = [
      Vl.new()
      |> Vl.data_from_values(%{
        r: radius_marks,
        theta: Enum.map(radius_marks, fn _ -> :math.pi() / 4 end)
      })
      |> Vl.mark(:text,
        color: "black",
        radius: [expr: "datum.r  * min(width, height) / (2 * #{max_radius})"],
        theta: :math.pi() / 2,
        dy: 10,
        dx: -10
      )
      |> Vl.encode_field(:text, "r", type: :quantitative)
    ]

    radius_marks_vl ++ radius_ruler_vl
  end

  def plot_data(vl, data, opts \\ []) do
    pi = :math.pi()
    legend_name = opts[:legend_name] || ""

    theta_offset = opts[:theta_offset] || 0

    radius_marks = opts[:radius_marks]
    max_radius = Enum.max(radius_marks)

    Vl.new()
    |> Vl.config(
      style: [cell: [stroke: "transparent"]],
      legend: [
        label_font_size: "20",
        title_font_size: "24",
        disable: false,
        symbol_type: "stroke",
        symbol_stroke_width: 12,
        symbol_size: 100
      ]
    )
    |> Vl.layers([
      vl
      | for {data, mark, mark_opts} <- data do
          Vl.new()
          |> Vl.data_from_values(data)
          |> Vl.transform(calculate: "datum.r * cos(datum.theta * #{pi / 180})", as: "x_linear")
          |> Vl.transform(calculate: "datum.r * sin(datum.theta * #{pi / 180})", as: "y_linear")
          |> Vl.transform(
            calculate:
              "datum.x_linear * cos(#{rad(theta_offset)}) - datum.y_linear * sin(#{rad(theta_offset)})",
            as: "x"
          )
          |> Vl.transform(
            calculate:
              "datum.x_linear * sin(#{rad(theta_offset)}) + datum.y_linear * cos(#{rad(theta_offset)})",
            as: "y"
          )
          |> Vl.mark(mark, mark_opts)
          |> Vl.encode_field(:color, legend_name, type: :nominal, scale: [scheme: "turbo"])
          |> then(fn vl ->
            if Map.has_key?(data, "stroke_dash") or Map.has_key?(data, :stroke_dash) do
              Vl.encode_field(vl, :stroke_dash, "stroke_dash", type: :quantitative)
            else
              vl
            end
          end)
          |> Vl.encode_field(:x, "y",
            type: :quantitative,
            scale: [
              domain: [-max_radius, max_radius]
            ],
            axis: [
              grid: false,
              ticks: false,
              domain_opacity: 0,
              labels: false,
              title: false,
              domain: false,
              offset: 50
            ]
          )
          |> Vl.encode_field(:y, "x",
            type: :quantitative,
            scale: [
              domain: [-max_radius, max_radius]
            ],
            axis: [
              grid: false,
              ticks: false,
              domain_opacity: 0,
              labels: false,
              title: false,
              domain: false,
              offset: 50
            ]
          )
          |> Vl.encode_field(:order, "theta")
          |> Vl.encode(
            :tooltip,
            Enum.map(data, fn {field, _} ->
              [field: to_string(field), type: :quantitative]
            end)
          )
        end
    ])
  end
end
