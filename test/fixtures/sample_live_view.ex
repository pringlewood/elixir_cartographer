# Sample LiveView fixtures for testing LiveViewAnalyzer
# This file is NOT compiled — it is read and parsed by the analyzer tests.

defmodule SampleApp.DashboardLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SampleApp.PubSub, "dashboard:updates")
    end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:count, 0)
     |> assign_new(:user, fn -> nil end)
     |> stream(:items, fetch_items())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("increment", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  @impl true
  def handle_event("save", %{"form" => form_params}, socket) do
    case save_item(form_params) do
      {:ok, item} ->
        {:noreply,
         socket
         |> stream_insert(:items, item)
         |> push_navigate(to: ~p"/items/#{item.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    item = get_item!(id)
    {:ok, _} = delete_item(item)
    {:noreply, stream_delete(socket, :items, item)}
  end

  @impl true
  def handle_event("validate", %{"form" => form_params}, socket) do
    changeset = validate_item(form_params)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_info({:item_updated, item}, socket) do
    {:noreply, stream_insert(socket, :items, item)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1><%= @page_title %></h1>
      <p>Count: <%= @count %></p>

      <button phx-click="increment">+1</button>

      <.live_component module={SampleApp.FormComponent} id="new-item" />

      <div id="items" phx-update="stream" phx-hook="InfiniteScroll">
        <div :for={{dom_id, item} <- @streams.items} id={dom_id}>
          <span><%= item.name %></span>
          <button phx-click={JS.push("delete", value: %{id: item.id}) |> JS.hide(to: "##{dom_id}")}>
            Delete
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp apply_action(socket, :index, _params), do: socket
  defp apply_action(socket, :edit, %{"id" => id}), do: assign(socket, :item, get_item!(id))
  defp fetch_items, do: []
  defp save_item(_params), do: {:ok, %{id: 1}}
  defp get_item!(_id), do: %{id: 1, name: "test"}
  defp delete_item(_item), do: {:ok, %{}}
  defp validate_item(_params), do: %{}
end

defmodule SampleApp.FormComponent do
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("submit", %{"form" => params}, socket) do
    send(self(), {:form_submitted, params})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit="submit" phx-target={@myself}>
        <input type="text" name="form[name]" />
        <button type="submit">Save</button>
      </form>
    </div>
    """
  end
end

defmodule SampleApp.Components do
  use Phoenix.Component

  attr :label, :string, required: true
  attr :type, :string, default: "button"
  attr :class, :string, default: ""
  attr :rest, :global

  slot :inner_block, required: true
  slot :icon

  def button(assigns) do
    ~H"""
    <button type={@type} class={["btn", @class]} {@rest}>
      <span :if={@icon != []}>
        <%= render_slot(@icon) %>
      </span>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  slot :inner_block, required: true
  slot :actions

  def card(assigns) do
    ~H"""
    <div class="card">
      <div class="card-header">
        <h2><%= @title %></h2>
        <p :if={@subtitle}><%= @subtitle %></p>
      </div>
      <div class="card-body">
        <%= render_slot(@inner_block) %>
      </div>
      <div :if={@actions != []} class="card-actions">
        <%= render_slot(@actions) %>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>Default render</div>
    """
  end
end

defmodule SampleApp.UploadLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:uploaded_files, [])
     |> allow_upload(:avatar, accept: ~w(.jpg .jpeg .png), max_entries: 3)}
  end

  @impl true
  def handle_event("save_upload", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
        dest = Path.join("priv/static/uploads", Path.basename(path))
        File.cp!(path, dest)
        {:ok, "/uploads/#{Path.basename(dest)}"}
      end)

    {:noreply, assign(socket, :uploaded_files, uploaded_files)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit="save_upload" phx-change="validate_upload">
        <.live_file_input upload={@uploads.avatar} />
        <button type="submit">Upload</button>
      </form>
    </div>
    """
  end
end

defmodule SampleApp.RealtimeLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SampleApp.PubSub, "notifications")
    end

    {:ok,
     socket
     |> assign(:notifications, [])
     |> push_event("init", %{})}
  end

  @impl true
  def handle_event("dismiss", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> update(:notifications, fn notifs -> Enum.reject(notifs, &(&1.id == id)) end)
     |> push_patch(to: ~p"/realtime")}
  end

  @impl true
  def handle_info({:new_notification, notif}, socket) do
    Phoenix.PubSub.broadcast(SampleApp.PubSub, "notifications:ack", {:received, notif.id})
    {:noreply, update(socket, :notifications, fn list -> [notif | list] end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="realtime" phx-hook="RealtimeHook">
      <div :for={notif <- @notifications}>
        <span><%= notif.message %></span>
        <button phx-click={JS.push("dismiss", value: %{id: notif.id}) |> JS.toggle(to: "#details")}>
          Dismiss
        </button>
      </div>
    </div>
    """
  end
end
