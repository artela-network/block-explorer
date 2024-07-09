defmodule BlockScoutWeb.API.V2.AspectView do
  use BlockScoutWeb, :view

  alias BlockScoutWeb.API.V2.ApiView

  alias Explorer.Chain
  alias Explorer.Chain.{Aspect, Transaction}

  def render("message.json", assigns) do
    ApiView.render("message.json", assigns)
  end

  def render("transactions.json", %{transactions: transactions, next_page_params: next_page_params}) do
    %{
      "items" =>
        transactions
        |> Enum.map(fn tx ->
          tx
          |> Map.merge(%{
            fee: %Transaction{gas_price: tx.gas_price, gas_used: tx.gas_used} |> Transaction.fee(:wei) |> format_fee(),
            result:
              %Transaction{status: tx.status, block_hash: tx.block_hash, error: tx.error}
              |> Chain.transaction_to_status()
              |> format_status()
          })
        end),
      "next_page_params" => next_page_params
    }
  end

  def render("bound_addresses.json", %{bound_addresses: bound_addresses, next_page_params: next_page_params}) do
    %{
      "items" =>
        bound_addresses
        |> Enum.map(fn ba ->
          ba
          |> Map.merge(%{
            is_smart_contract: is_smart_contract(ba.contract_code)
          })
          |> Map.delete(:cotract_code)
        end),
      "next_page_params" => next_page_params
    }
  end

  def render("aspects.json", %{aspects: aspects, next_page_params: next_page_params}) do
    %{
      "items" =>
        aspects
        |> Enum.map(fn aspect ->
          aspect
          |> Map.merge(%{
            join_points: Aspect.decode_join_points(aspect.join_points)
          })
        end),
      "next_page_params" => next_page_params
    }
  end

  def render("aspect.json", %{aspect: aspect}) do
    prepare_aspect(aspect)
  end

  defp prepare_aspect(%Aspect{} = aspect) do
    base_info = %{
      hash: aspect.hash,
      join_points: Aspect.decode_join_points(aspect.join_points),
      properties: aspect.properties
    }

    current_version =
      aspect.versions |> Enum.filter(fn version -> version.version == aspect.version end) |> List.first()

    bound_address_count = Aspect.address_binding_count(aspect.hash)

    base_info
    |> Map.merge(%{
      deployed_tx: current_version.aspect_transaction_hash,
      bound_address_count: bound_address_count,
      versions: prepare_versions(aspect.versions)
    })
  end

  def prepare_versions(versions) do
    Enum.map(versions, &prepare_version(&1))
  end

  def prepare_version(version) do
    %{
      "version" => version.version,
      "aspect_transaction_hash" => version.aspect_transaction_hash,
      "aspect_transaction_index" => version.aspect_transaction_index,
      "block_number" => version.block_number,
      "properties" => version.properties,
      "join_points" => Aspect.decode_join_points(version.join_points)
    }
  end

  defp format_fee({type, value}), do: %{"type" => type, "value" => value}

  defp format_status({:error, reason}), do: reason
  defp format_status(status), do: status

  defp is_smart_contract(contract_code) do
    case contract_code do
      nil -> false
      _ -> true
    end
  end
end
