defmodule NauticNetWeb.ErrorJSONTest do
  use NauticNetWeb.ConnCase, async: true

  test "renders 404" do
    assert NauticNetWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert NauticNetWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
