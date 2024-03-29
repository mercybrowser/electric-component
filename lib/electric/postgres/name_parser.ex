defmodule Electric.Postgres.NameParser do
  import NimbleParsec

  identifier =
    choice([
      # quoted identifier
      ignore(string(~s(")))
      |> repeat(
        choice([
          string(~s("")) |> replace(~s(")),
          utf8_char(not: ?")
        ])
      )
      |> ignore(string(~s(")))
      |> tag(:quoted),
      # unquoted identifier
      utf8_char([])
      |> repeat_while({:unquoted_name, []})
      |> tag(:unquoted)
    ])

  namespaced =
    optional(
      concat(
        identifier,
        ignore(string("."))
      )
      |> tag(:schema)
    )
    |> concat(identifier |> tag(:name))

  defparsec(:parse_name, identifier)
  defparsec(:parse_namespaced, namespaced)

  def parse(name, opts \\ []) do
    with {:ok, parsed, "", _, _, _} <- parse_namespaced(name),
         {:ok, name} <- Keyword.fetch(parsed, :name),
         schema =
           Keyword.get(parsed, :schema, quoted: Keyword.get(opts, :default_schema, "public")) do
      {:ok, {identifier(schema), identifier(name)}}
    end
  end

  defp identifier([{:quoted, ident}]) do
    to_string(ident)
  end

  defp identifier([{:unquoted, ident}]) do
    String.downcase(to_string(ident))
  end

  def parse!(name, opts \\ []) do
    case parse(name, opts) do
      {:ok, name} ->
        name

      error ->
        raise ArgumentError, message: "Failed to parse name #{inspect(name)}: #{inspect(error)}"
    end
  end

  # used to find the end of an unquoted name, so allows the parser to continue
  # until it hits whitespace, or a quote
  defp unquoted_name(<<w::8, _::binary>>, context, _, _) when w in [?\s, ?\r, ?\n, ?\t],
    do: {:halt, context}

  defp unquoted_name(<<?., _::binary>>, context, _, _), do: {:halt, context}
  defp unquoted_name(<<?", _::binary>>, context, _, _), do: {:halt, context}
  defp unquoted_name(<<?', _::binary>>, context, _, _), do: {:halt, context}
  defp unquoted_name(_, context, _, _), do: {:cont, context}
end
