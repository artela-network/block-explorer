defmodule Explorer.Chain.Aspect do
  @moduledoc """
  A stored representation of aspect lastest version.
  """

  use Explorer.Schema

  import Bitwise
  import Explorer.Chain, only: [add_fetcher_limit: 2, select_repo: 1, join_associations: 2]

  alias Explorer.Chain.{Aspect, Data, Hash}
  alias Explorer.{Repo, Chain}
  alias Explorer.Chain.Aspect.{BoundAddress, Version, Transaction}

  @constant "0x0000000000000000000000000000000000a27e14"

  @optional_attrs ~w(properties proof join_points settlement_address_hash code version)a
  @required_attrs ~w(hash)a
  @allowed_attrs @optional_attrs ++ @required_attrs

  @typedoc """
   * `hash` - aspect ID
   * `version` - aspect lastest version
   * `properties` - aspect latest deployed properties
   * `join_points` - aspect latest join_points
   * `code` - aspect latest deployed Bytecode of the Aspect's WASM artifact
  """

  @primary_key false
  typed_schema "aspects" do
    field(:hash, Hash.Address, primary_key: true)
    field(:settlement_address_hash, Hash.Address)
    field(:properties, :map)
    field(:version, :integer)
    field(:code, Data)
    field(:proof, :binary)
    field(:join_points, :integer)

    has_many(:transactions, Aspect.Transaction, foreign_key: :aspect_hash, references: :hash)
    has_many(:versions, Aspect.Version, foreign_key: :aspect_hash, references: :hash)
    has_many(:bound_addresses, Aspect.BoundAddress, foreign_key: :aspect_hash, references: :hash)

    timestamps()
  end

  def changeset(%__MODULE__{} = aspect, attrs) do
    aspect
    |> cast(attrs, @allowed_attrs)
    |> validate_required(@required_attrs)
    |> unique_constraint(:hash)
  end

  def constant, do: @constant

  def find_by_hash(aspect_hash) do
    Aspect |> Repo.get_by(hash: aspect_hash)
  end

  def stream_unversioned_aspect_hashes(initial, reducer, limited? \\ false)
      when is_function(reducer, 2) do
    query =
      from(
        version1 in Version,
        join: version2 in Version,
        on: version2.aspect_hash == version1.aspect_hash,
        where: version1.version == 1 and is_nil(version2.version),
        select: version1.aspect_hash,
        distinct: true
      )

    query
    |> add_fetcher_limit(limited?)
    |> Repo.stream_reduce(initial, reducer)
  end

  def stream_unbind_addresses(initial, reducer, limited? \\ false)
      when is_function(reducer, 2) do
    query =
      from(
        bound_address1 in BoundAddress,
        join: bound_address2 in BoundAddress,
        on:
          bound_address1.aspect_hash == bound_address2.aspect_hash and
            bound_address1.bound_address_hash == bound_address2.bound_address_hash,
        where:
          is_nil(bound_address1.bind_aspect_transaction_hash) and
            not is_nil(bound_address2.bind_aspect_transaction_hash) and
            (is_nil(bound_address2.unbind_aspect_transaction_hash) or
               (bound_address2.bind_block_number < bound_address1.unbind_block_number and
                  bound_address2.unbind_block_number > bound_address1.unbind_block_number)),
        select: bound_address1
      )

    query
    |> add_fetcher_limit(limited?)
    |> Repo.stream_reduce(initial, reducer)
  end

  def stream_unhandled_aspect_transaction(initial, reducer, limited? \\ false)
      when is_function(reducer, 2) do
    query =
      from(
        bound_address in BoundAddress,
        where:
          not is_nil(bound_address.bind_block_nubmer) and
            bound_address.block_nubmer_checkpoint != bound_address.unbind_block_number,
        order_by: [asc: :checkpoint_block_number]
      )

    query
    |> add_fetcher_limit(limited?)
    |> Repo.stream_reduce(initial, reducer)
  end

  @spec aspect_binding_count(Hash.Address.t()) :: non_neg_integer()
  def aspect_binding_count(address_hash) do
    query =
      from(
        bound_address in BoundAddress,
        where: is_nil(bound_address.unbind_aspect_transaction_hash),
        where: bound_address.bound_address_hash == ^address_hash
      )

    Repo.aggregate(query, :count, :aspect_hash, timeout: :infinity)
  end

  def list_transactions(aspect_hash, options \\ []) do
    paging_options = Keyword.get(options, :paging_options, Chain.default_paging_options())

    Transaction.list_transactions(aspect_hash)
    |> Transaction.page_transaction(paging_options)
    |> limit(^paging_options.page_size)
    |> select_repo(options).all()
  end

  def list_bound_addresses(aspect_hash, options \\ []) do
    paging_options = Keyword.get(options, :paging_options, Chain.default_paging_options())

    BoundAddress.list_bound_addresses(aspect_hash)
    |> BoundAddress.page_bound_address(paging_options)
    |> limit(^paging_options.page_size)
    |> select_repo(options).all()
  end

  def address_hash_to_aspects(address_hash, options \\ []) do
    paging_options = Keyword.get(options, :paging_options, Chain.default_paging_options())

    BoundAddress.address_hash_to_aspects_query(address_hash)
    |> BoundAddress.page_bound_address(paging_options)
    |> limit(^paging_options.page_size)
    |> select_repo(options).all()
  end

  def hash_to_aspect(
        hash,
        options \\ [
          necessity_by_association: %{
            :versions => :optional
          }
        ]
      ) do
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})

    query =
      from(
        aspect in Aspect,
        where: aspect.hash == ^hash
      )

    query
    |> join_associations(necessity_by_association)
    |> select_repo(options).one()
    |> case do
      nil -> {:error, :not_found}
      aspect -> {:ok, aspect}
    end
  end

  @spec address_binding_count(Hash.Address.t()) :: non_neg_integer()
  def address_binding_count(aspect_hash) do
    query =
      from(
        bound_address in BoundAddress,
        where: is_nil(bound_address.unbind_aspect_transaction_hash),
        where: bound_address.aspect_hash == ^aspect_hash
      )

    Repo.aggregate(query, :count, :bound_address_hash, timeout: :infinity)
  end

  def decode_join_points(join_points) do
    [
      {"verify_tx", 1},
      {"pre_tx_execute", 2},
      {"pre_contract_call", 4},
      {"post_contract_call", 8},
      {"post_tx_execute", 16},
      {"post_tx_commit", 32}
    ]
    |> Enum.filter(fn {_name, value} -> (join_points &&& value) != 0 end)
    |> Enum.map(fn {name, _} -> name end)
  end
end
