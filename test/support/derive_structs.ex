require Protocol

defmodule TomlElixir.TestStructs.User do
  @moduledoc false
  @derive TomlElixir.Encoder
  defstruct [:name, :age]
end

defmodule TomlElixir.TestStructs.UserOnly do
  @moduledoc false
  @derive {TomlElixir.Encoder, only: [:name]}
  defstruct [:name, :age, :password]
end

defmodule TomlElixir.TestStructs.UserExcept do
  @moduledoc false
  @derive {TomlElixir.Encoder, except: [:password]}
  defstruct [:name, :age, :password]
end

defmodule TomlElixir.TestStructs.UserOnlyWins do
  @moduledoc false
  @derive {TomlElixir.Encoder, only: [:name, :age], except: [:age]}
  defstruct [:name, :age, :password]
end

defmodule TomlElixir.TestStructs.Other do
  @moduledoc false
  defstruct [:foo]
end

defmodule TomlElixir.TestStructs.ProtocolDerived do
  @moduledoc false
  defstruct [:name, :age, :password]
end

Protocol.derive(TomlElixir.Encoder, TomlElixir.TestStructs.ProtocolDerived, only: [:name])

defmodule TomlElixir.TestStructs.Nested.Complex.ModuleName do
  @moduledoc false
  @derive TomlElixir.Encoder
  defstruct [:field]
end
