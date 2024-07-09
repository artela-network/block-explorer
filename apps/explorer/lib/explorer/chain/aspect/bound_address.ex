defmodule Explorer.Chain.Aspect.BoundAddress do
  @moduledoc """
  Aspect bound addresses.
  """

  use Explorer.Schema

  import Ecto.Changeset

  alias Explorer.Chain.{Aspect, Address, Hash}
  alias Explorer.PagingOptions
  alias Explorer.Chain.Aspect.Version, as: AspectVersion

  @typedoc """
  * `aspect` - the `t:Explorer.Chain.Aspect.t/0` .
  * `aspect_hash` - foreign key for `address`.
  * `version` - the version of aspect.
  * `priority` - the lowest priority number being executed first, an unsigned 8-bit integer.
  """

  typed_schema "aspect_bound_addresses" do
    field(:priority, :integer)
    field(:version, :integer)
    field(:checkpoint_block_number, :integer)
    field(:bind_block_number, :integer)
    field(:unbind_block_number, :integer)
    field(:bind_aspect_transaction_index, :integer)
    field(:unbind_aspect_transaction_index, :integer)

    belongs_to(:address, Address, foreign_key: :bound_address_hash, references: :hash, type: Hash.Address, null: false)
    belongs_to(:aspect, Aspect, foreign_key: :aspect_hash, references: :hash, type: Hash.Address, null: false)

    belongs_to(:aspect_transaction, Aspect.Transaction,
      foreign_key: :bind_aspect_transaction_hash,
      references: :hash,
      type: Hash.Full
    )

    belongs_to(:aspect_unbind_transaction, Aspect.Transaction,
      foreign_key: :unbind_aspect_transaction_hash,
      references: :hash,
      type: Hash.Full
    )

    timestamps()
  end

  @required_fields ~w(aspect_hash bound_address_hash)a
  @optional_fields ~w(version unbind_block_number unbind_aspect_transaction_hash unbind_aspect_transaction_index bind_aspect_transaction_hash bind_block_number bind_aspect_transaction_index priority checkpoint_block_number)a
  @allowed_fields @required_fields ++ @optional_fields

  def changeset(%__MODULE__{} = struct, params \\ %{}) do
    struct
    |> cast(params, @allowed_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:aspect_hash)
    |> unique_constraint([:bind_block_number, :bind_aspect_transaction_index])
  end

  @spec list_bound_addresses(String.t()) :: Ecto.Query.t()
  def list_bound_addresses(aspect_hash) do
    from(ba in __MODULE__,
      join: a in Address,
      on: a.hash == ba.bound_address_hash,
      where: ba.aspect_hash == ^aspect_hash,
      where: is_nil(ba.unbind_aspect_transaction_hash),
      select: %{
        bound_address_hash: ba.bound_address_hash,
        bind_aspect_transaction_hash: ba.bind_aspect_transaction_hash,
        bind_aspect_transaction_index: ba.bind_aspect_transaction_index,
        bind_block_number: ba.bind_block_number,
        version: ba.version,
        priority: ba.priority,
        contract_code: a.contract_code
      },
      order_by: [desc: :bind_block_number, desc: :bind_aspect_transaction_index]
    )
  end

  def address_hash_to_aspects_query(address_hash) do
    from(ba in __MODULE__,
      join: v in AspectVersion,
      on: v.aspect_hash == ba.aspect_hash and v.version == ba.version,
      where: ba.bound_address_hash == ^address_hash,
      where: is_nil(ba.unbind_aspect_transaction_hash),
      select: %{
        aspect_hash: ba.aspect_hash,
        version: ba.version,
        priority: ba.priority,
        join_points: v.join_points
      },
      order_by: [desc: :bind_block_number, desc: :bind_aspect_transaction_index]
    )
  end

  @spec page_bound_address(Ecto.Query.t() | atom, Explorer.PagingOptions.t()) :: Ecto.Query.t()
  def page_bound_address(query, %PagingOptions{key: nil}), do: query

  def page_bound_address(query, %PagingOptions{key: {block_number, index}, is_index_in_asc_order: true}) do
    where(
      query,
      [bound_address],
      bound_address.bind_block_number < ^block_number or
        (bound_address.bind_block_number == ^block_number and bound_address.bind_aspect_transaction_index > ^index)
    )
  end

  def page_bound_address(query, %PagingOptions{key: {block_number, index}}) do
    where(
      query,
      [bound_address],
      bound_address.bind_block_number < ^block_number or
        (bound_address.bind_block_number == ^block_number and bound_address.bind_aspect_transaction_index < ^index)
    )
  end
end
