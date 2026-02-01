defmodule SampleAppWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug SampleAppWeb.Plugs.Auth
  end

  scope "/", SampleAppWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/about", PageController, :about
  end

  scope "/api/v1", SampleAppWeb.API do
    pipe_through :api

    get "/users", UserController, :index
    post "/users", UserController, :create
    get "/users/:id", UserController, :show
    put "/users/:id", UserController, :update
    delete "/users/:id", UserController, :delete
  end

  scope "/admin", SampleAppWeb.Admin do
    pipe_through [:browser, :admin_auth]

    live "/dashboard", DashboardLive, :index
    live "/users", UsersLive, :index
    live "/users/:id", UsersLive, :show
  end
end
