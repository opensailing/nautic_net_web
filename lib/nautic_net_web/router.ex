defmodule NauticNetWeb.Router do
  use NauticNetWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {NauticNetWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", NauticNetWeb do
    pipe_through :browser
  end

  scope "/", NauticNetWeb do
    pipe_through :browser

    get "/home", PageController, :home

    live "/", MapLive
    live "/boats", BoatsLive
  end

  scope "/api", NauticNetWeb.API do
    pipe_through :api

    post "/data_sets", DataSetController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", NauticNetWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:nautic_net, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard",
        metrics: NauticNetWeb.Telemetry,
        additional_pages: [
          flame_on: FlameOn.DashboardPage
        ]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
