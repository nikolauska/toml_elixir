# This file contains the configuration for Credo and you are probably reading
# this after creating it with `mix credo.gen.config`.
#
# If you find anything wrong or unclear in this file, please report an
# issue on GitHub: https://github.com/rrrene/credo/issues
#
%{
  #
  # You can have as many configs as you like in the `configs:` field.
  configs: [
    %{
      #
      # Run any config using `mix credo -C <name>`. If no config name is given
      # "default" is used.
      #
      name: "default",
      #
      # These are the files included in the analysis:
      files: %{
        #
        # You can give explicit globs or simply directories.
        # In the latter case `**/*.{ex,exs}` will be used.
        #
        included: [
          "lib/",
          "test/"
        ],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      #
      # Load and configure plugins here:
      #
      plugins: [
        {ExSlop, []}
      ],
      #
      # If you create your own checks, you must specify the source files for
      # them here, so they can be loaded by Credo before running the analysis.
      #
      requires: [],
      #
      # If you want to enforce a style guide and need a more traditional linting
      # experience, you can change `strict` to `true` below:
      #
      strict: true,
      #
      # To modify the timeout for parsing files, change this value:
      #
      parse_timeout: 5000,
      #
      # If you want to use uncolored output by default, you can change `color`
      # to `false` below:
      #
      color: true,
      #
      # You can customize the parameters of any check by adding a second element
      # to the tuple.
      #
      # To disable a check put `false` as second element:
      #
      #     {Credo.Check.Design.DuplicatedCode, false}
      #
      checks: [
        {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 19},
        {Credo.Check.Refactor.Nesting, max_nesting: 4},

        # Catches length(list) == 0 (traverses entire list) → use list == [] or Enum.empty?/1
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},

        # Catches acc ++ [item] (O(n²) append) → use [item | acc] then Enum.reverse
        {Credo.Check.Refactor.AppendSingleItem, []},

        # Catches !!var (double negation) → LLMs use this to "cast to boolean"
        {Credo.Check.Refactor.DoubleBooleanNegation, []},

        # Catches case x do true -> a; false -> b end → if/else
        {Credo.Check.Refactor.CondStatements, []},

        # Catches Enum.map |> Enum.map → single Enum.map
        {Credo.Check.Refactor.MapMap, []},

        # Catches Enum.filter |> Enum.filter → single Enum.filter
        {Credo.Check.Refactor.FilterFilter, []},

        # Catches Enum.reject |> Enum.reject → single Enum.reject
        {Credo.Check.Refactor.RejectReject, []},

        # Catches Enum.count(enum) > 0 → Enum.any?/1
        {Credo.Check.Refactor.FilterCount, []},

        # Catches negated conditions in unless → rewrite with positive condition
        {Credo.Check.Refactor.NegatedConditionsInUnless, []},

        # Catches unless x do .. else .. end → if/else (clearer)
        {Credo.Check.Refactor.UnlessWithElse, []}
      ]
    }
  ]
}
