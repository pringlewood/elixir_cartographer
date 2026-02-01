defmodule SampleApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias SampleApp.Accounts.Role
  alias SampleApp.Organizations.Organization

  schema "users" do
    field :email, :string
    field :name, :string
    field :status, :string, default: "active"
    field :role, :string
    field :encrypted_password, :string

    belongs_to :organization, Organization
    has_many :roles, Role

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :status, :role])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:name, min: 2, max: 100)
    |> validate_inclusion(:status, ["active", "inactive", "suspended"])
    |> unique_constraint(:email)
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> validate_required([:encrypted_password])
  end

  def activate(user), do: change_status(user, "active")
  def deactivate(user), do: change_status(user, "inactive")
  def suspend(user), do: change_status(user, "suspended")

  defp change_status(user, status) do
    user
    |> changeset(%{status: status})
  end
end
