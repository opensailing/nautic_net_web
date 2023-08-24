defmodule NauticNetWeb.PageControllerTest do
  use NauticNetWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/home")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end
end
